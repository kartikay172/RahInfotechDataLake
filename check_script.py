import sys, boto3, io, csv, json, logging, hashlib, re, subprocess
from datetime import datetime
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)
from awsglue.utils import getResolvedOptions

args = getResolvedOptions(sys.argv, ["JOB_NAME","SOURCE_BUCKET","SOURCE_PREFIX","DEST_PREFIX","SECRET_NAME","REGION_NAME"])
SOURCE_BUCKET = args["SOURCE_BUCKET"]
SOURCE_PREFIX = args["SOURCE_PREFIX"]
DEST_PREFIX   = args["DEST_PREFIX"]
SECRET_NAME   = args["SECRET_NAME"]
REGION_NAME   = args["REGION_NAME"]

secrets_client = boto3.client("secretsmanager", region_name=REGION_NAME)
secret_value   = secrets_client.get_secret_value(SecretId=SECRET_NAME)
secret_dict    = json.loads(secret_value["SecretString"])
PII_SALT       = secret_dict.get("pii_salt", "default_salt")

subprocess.check_call([sys.executable, "-m", "pip", "install", "openpyxl", "-q"])
import openpyxl

s3 = boto3.client("s3", region_name=REGION_NAME)

PII_NAME_PATTERNS = [r"name",r"email",r"phone",r"mobile",r"address",r"ssn",r"passport",r"aadhaar",r"pan"]
PII_DATE_PATTERNS = [r"dob",r"doj",r"date.?of.?birth",r"date.?of.?join",r"joining",r"birth"]

def is_pii_name(col): return any(re.search(p, col.lower()) for p in PII_NAME_PATTERNS)
def is_pii_date(col): return any(re.search(p, col.lower()) for p in PII_DATE_PATTERNS)

def mask_name(v):
    if not v or len(v)<2: return "***"
    vis = min(3, len(v)//2)
    return v[:vis] + "*"*(len(v)-vis)

def hash_value(v):
    return hashlib.sha256(f"{PII_SALT}:{v}".encode()).hexdigest()[:16]

def detect_type(v):
    if v is None or str(v).strip()=="": return None,"null"
    s = str(v).strip()
    if s.lower() in ("true","false","yes","no"): return s,"boolean"
    try: return int(s.replace(",","")), "integer"
    except: pass
    try: return float(s.replace(",","")), "float"
    except: pass
    for fmt in ("%Y-%m-%d","%d-%m-%Y","%d/%m/%Y","%m/%d/%Y","%d-%b-%Y"):
        try: return datetime.strptime(s,fmt).strftime("%Y-%m-%d"),"date"
        except: pass
    return s,"string"

def infer_types(rows, headers):
    votes = {h:{} for h in headers}
    for row in rows:
        for i,v in enumerate(row):
            if i>=len(headers): continue
            _,t = detect_type(v)
            votes[headers[i]][t] = votes[headers[i]].get(t,0)+1
    priority = ["date","boolean","integer","float","string"]
    result = {}
    for h in headers:
        v = {k:n for k,n in votes[h].items() if k!="null"}
        if not v: result[h]="string"; continue
        for p in priority:
            if p in v and v[p]==max(v.values()): result[h]=p; break
        else: result[h]=max(v,key=v.get)
    return result

now = datetime.utcnow()
PARTITION = f"year={now.year}/month={now.month:02d}/day={now.day:02d}"

paginator = s3.get_paginator("list_objects_v2")
xlsx_keys = [
    obj["Key"]
    for page in paginator.paginate(Bucket=SOURCE_BUCKET, Prefix=SOURCE_PREFIX)
    for obj in page.get("Contents",[])
    if obj["Key"].lower().endswith(".xlsx")
]
logger.info(f"Found {len(xlsx_keys)} Excel files. Partition: {PARTITION}")

for key in xlsx_keys:
    logger.info(f"Processing: {key}")
    try:
        obj = s3.get_object(Bucket=SOURCE_BUCKET, Key=key)
        wb  = openpyxl.load_workbook(io.BytesIO(obj["Body"].read()), data_only=True)
        for sheet_name in wb.sheetnames:
            ws   = wb[sheet_name]
            rows = list(ws.values)
            if len(rows)<2: continue
            headers  = [str(h).strip() if h else f"col_{i}" for i,h in enumerate(rows[0])]
            data     = [[str(c).replace(chr(10), " | ").replace(chr(13), "") if c is not None else "" for c in r] for r in rows[1:] if any(c is not None for c in r)]
            if not data: continue
            col_types = infer_types(data, headers)
            transformed = []
            for row in data:
                out = []
                for i,val in enumerate(row):
                    if i>=len(headers): continue
                    h = headers[i]
                    cast_val,_ = detect_type(val)
                    s = str(cast_val) if cast_val is not None else ""
                    if is_pii_name(h): s = mask_name(s)
                    elif is_pii_date(h): s = hash_value(s)
                    out.append(s)
                transformed.append(out)
            rel       = key[len(SOURCE_PREFIX):]
            folder    = rel.rsplit("/",1)[0] if "/" in rel else ""
            stem      = rel.rsplit("/",1)[-1].replace(".xlsx","").replace(" ","_")
            slug      = sheet_name.replace(" ","_")
            data_key  = f"{DEST_PREFIX}{folder}/{stem}/{slug}/{PARTITION}/data.csv"
            meta_key  = f"{DEST_PREFIX}{folder}/{stem}/{slug}/{PARTITION}/schema.json"
            buf = io.StringIO()
            csv.writer(buf).writerow(headers)
            csv.writer(buf).writerows(transformed)
            s3.put_object(Bucket=SOURCE_BUCKET, Key=data_key, Body=buf.getvalue().encode(), ContentType="text/csv")
            schema = {"source":key,"sheet":sheet_name,"processed_at":now.isoformat(),"partition":PARTITION,
                "columns":[{"name":h,"type":col_types.get(h,"string"),
                    "pii":is_pii_name(h) or is_pii_date(h),
                    "pii_treatment":"masked" if is_pii_name(h) else "hashed" if is_pii_date(h) else "none"}
                for h in headers]}
            s3.put_object(Bucket=SOURCE_BUCKET, Key=meta_key, Body=json.dumps(schema,indent=2).encode(), ContentType="application/json")
            logger.info(f"Written {len(transformed)} rows -> {data_key}")
    except Exception as e:
        logger.error(f"Failed {key}: {e}")
        import traceback; traceback.print_exc()

logger.info("Done.")