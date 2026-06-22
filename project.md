# Project: Data Transfer from SharePoint to S3

## Overview

This project provisions a fully automated AWS data pipeline that extracts data from SharePoint, lands it in S3 via AppFlow, transforms Excel files into queryable CSV format using AWS Glue, and exposes the data for analysis through Amazon Athena — all managed with Terraform.

---

## Architecture

```
SharePoint Online
      │
      ▼
Amazon AppFlow  ──────────────────────────────────────────────────────────────────────┐
(SharePoint → S3 connector, configured manually in console)                           │
      │                                                                               │
      ▼                                                                               │
S3 Bucket  (sharepoint-backup/)  ◄──────────────────────────────────────── Raw .xlsx │
      │                                                                               │
      ▼                                                                               │
AWS Glue ETL Job  (glue_etl_script.py)                                                │
   • Reads .xlsx from sharepoint-backup/                                              │
   • Converts each sheet → CSV                                                        │
   • Writes to processed/                                                             │
      │
      ▼
S3 Bucket  (processed/)
      │
      ▼
AWS Glue Crawler
   • Crawls processed/ prefix
   • Populates Glue Data Catalog (sharepoint_db)
      │
      ▼
Amazon Athena Workgroup
   • Queries Glue catalog tables
   • Stores results in athena-results/
```

---

## AWS Services Used

| Service | Purpose |
|---|---|
| Amazon S3 | Central data store (raw, processed, results, scripts) |
| Amazon AppFlow | Managed connector — pulls files from SharePoint to S3 |
| AWS Glue ETL Job | Converts .xlsx files to CSV (Python 3, Glue 4.0) |
| AWS Glue Crawler | Infers schema and populates Glue Data Catalog |
| AWS Glue Data Catalog | Metadata store / database for processed tables |
| Amazon Athena | SQL query engine over processed CSV data |
| AWS IAM | Roles and policies for AppFlow, Glue, and Athena access |

---

## Project File Structure

```
DataTransferFromSharepointToS3/
├── provider.tf          # AWS provider config, Terraform version constraints
├── variables.tf         # All input variables with defaults
├── s3.tf                # S3 bucket, versioning, encryption, public access block, AppFlow bucket policy
├── iam.tf               # IAM roles & policies for AppFlow, Glue, and Athena
├── glue.tf              # Glue catalog database, ETL job, Glue Crawler, S3 script upload
├── athena.tf            # Athena workgroup with result location
├── output.tf            # Terraform outputs (bucket, database, crawler, workgroup, policy ARN)
├── glue_etl_script.py   # PySpark/Boto3 ETL script (xlsx → CSV converter)
└── project.md           # This file
```

---

## Infrastructure Components

### S3 Bucket (`s3.tf`)
- Single bucket for all data (configurable name via `var.bucket_name`)
- Versioning enabled
- AES-256 server-side encryption
- All public access blocked
- Bucket policy allows AppFlow service principal to write objects

### IAM (`iam.tf`)
- `appflow-s3-role` — assumed by AppFlow, grants `s3:PutObject / GetBucketAcl / PutObjectAcl / ListBucket`
- `glue-crawler-role` — assumed by Glue, attaches `AWSGlueServiceRole` + inline S3 read policy
- `athena-query-policy` — standalone managed policy (attach to any user/role needing Athena access), grants Athena, Glue metadata, and S3 read/write

### Glue (`glue.tf`)
- Glue Catalog Database: `sharepoint_db`
- S3 object upload: deploys `glue_etl_script.py` to `s3://<bucket>/glue-scripts/sharepoint_etl.py`
- Glue ETL Job:
  - Runtime: Glue 4.0, Python 3
  - Worker: 2x G.1X
  - Timeout: 60 min
  - Job bookmark enabled (incremental processing)
  - CloudWatch logging and metrics enabled
  - Arguments: SOURCE_BUCKET, SOURCE_PREFIX, DEST_PREFIX
- Glue Crawler: crawls `processed/` prefix, updates catalog schema on change

### Athena (`athena.tf`)
- Workgroup: `<project_name>-workgroup`
- Results stored at `s3://<bucket>/athena-results/`
- CloudWatch metrics publishing enabled

---

## Input Variables

| Variable | Default | Description |
|---|---|---|
| `aws_region` | `us-east-1` | Target AWS region |
| `project_name` | `sharepoint-data` | Prefix for all resource names |
| `bucket_name` | _(required)_ | Globally unique S3 bucket name |
| `raw_data_prefix` | `raw-data/` | S3 prefix for CSV exports |
| `athena_results_prefix` | `athena-results/` | S3 prefix for Athena query results |
| `glue_database_name` | `sharepoint_db` | Glue catalog database name |
| `sharepoint_backup_prefix` | `sharepoint-backup/` | S3 prefix where AppFlow lands SharePoint files |
| `backup_glacier_transition_days` | `90` | Days before transitioning backup files to cheaper storage |

---

## Outputs

| Output | Description |
|---|---|
| `data_bucket_name` | Name of the S3 data bucket |
| `glue_database_name` | Glue catalog database name |
| `glue_crawler_name` | Name of the Glue crawler |
| `athena_workgroup_name` | Name of the Athena workgroup |
| `athena_query_policy_arn` | ARN of the Athena query IAM policy to attach to users/roles |

---

## ETL Script Logic (`glue_etl_script.py`)

1. Reads job arguments: `SOURCE_BUCKET`, `SOURCE_PREFIX`, `DEST_PREFIX`
2. Lists all `.xlsx` files under `SOURCE_PREFIX` using S3 paginator
3. For each Excel file:
   - Downloads and loads with `openpyxl`
   - Iterates over every sheet (skips sheets with < 2 rows)
   - Writes each sheet as a CSV to `DEST_PREFIX/<folder>/<filename>/<sheet_name>.csv`
4. Logs progress and completion to CloudWatch via standard logging

---

## Deployment Steps

### Prerequisites
- Terraform >= 1.5.0
- AWS CLI configured with sufficient permissions
- SharePoint Online credentials / OAuth app registration (for AppFlow connector)

### Deploy Infrastructure
```bash
terraform init
terraform plan -var="bucket_name=<your-unique-bucket-name>"
terraform apply -var="bucket_name=<your-unique-bucket-name>"
```

### Configure AppFlow (Manual — Console)
1. Go to **Amazon AppFlow** in AWS Console
2. Create a new flow: SharePoint → S3
3. Set destination bucket to the Terraform-created bucket
4. Set destination prefix to `sharepoint-backup/`
5. Schedule or trigger as needed

### Run the Pipeline
```bash
# Trigger Glue ETL job
aws glue start-job-run --job-name sharepoint-data-etl-job

# After job completes, run the crawler
aws glue start-crawler --name sharepoint-data-crawler

# Query data via Athena
aws athena start-query-execution \
  --query-string "SELECT * FROM sharepoint_db.<table> LIMIT 10;" \
  --work-group sharepoint-data-workgroup
```

---

## Security Considerations

- S3 bucket has all public access blocked; data is only accessible via IAM
- AppFlow and Glue each use least-privilege IAM roles scoped to the single bucket
- Athena query policy is a standalone managed policy — attach only to principals that need query access
- S3 bucket uses AES-256 encryption at rest
- AppFlow bucket policy restricts writes to the same AWS account via `aws:SourceAccount` condition

---

## Cost Drivers

| Component | Billing Model |
|---|---|
| S3 | Storage GB + request counts |
| AppFlow | Per flow run + records transferred |
| Glue ETL Job | DPU-hours (2x G.1X workers) |
| Glue Crawler | DPU-hours crawled |
| Athena | Per TB of data scanned |

> For cost estimates, use the [AWS Pricing Calculator](https://calculator.aws).
