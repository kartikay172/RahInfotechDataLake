import sys, boto3, io, csv, logging
import pandas as pd
import pyarrow as pa
import pyarrow.parquet as pq
import subprocess

subprocess.check_call([sys.executable, "-m", "pip", "install", "pyarrow", "pandas", "-q"])

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

from awsglue.utils import getResolvedOptions
args = getResolvedOptions(sys.argv, ["JOB_NAME", "SOURCE_BUCKET", "SOURCE_PREFIX", "DEST_PREFIX", "REGION_NAME"])

s3 = boto3.client("s3", region_name=args["REGION_NAME"])
SOURCE_BUCKET = args["SOURCE_BUCKET"]
SOURCE_PREFIX = args["SOURCE_PREFIX"]
DEST_PREFIX   = args["DEST_PREFIX"]

paginator = s3.get_paginator("list_objects_v2")
csv_keys = [
    obj["Key"]
    for page in paginator.paginate(Bucket=SOURCE_BUCKET, Prefix=SOURCE_PREFIX)
    for obj in page.get("Contents", [])
    if obj["Key"].lower().endswith(".csv")
]

logger.info(f"Found {len(csv_keys)} CSV files to convert")

for key in csv_keys:
    try:
        obj    = s3.get_object(Bucket=SOURCE_BUCKET, Key=key)
        df     = pd.read_csv(io.BytesIO(obj["Body"].read()))

        # Normalize column names
        df.columns = [c.lower().strip().replace(" ", "_").replace(".", "_") for c in df.columns]

        # Convert to Parquet
        buf   = io.BytesIO()
        table = pa.Table.from_pandas(df, preserve_index=False)
        pq.write_table(table, buf, compression="snappy")
        buf.seek(0)

        # Write to destination with .parquet extension
        dest_key = DEST_PREFIX + key[len(SOURCE_PREFIX):].replace(".csv", ".parquet")
        s3.put_object(Bucket=SOURCE_BUCKET, Key=dest_key, Body=buf.read())
        logger.info(f"Converted: {key} -> {dest_key}")

    except Exception as e:
        logger.error(f"Failed {key}: {e}")

logger.info("Conversion complete.")