# ── Power BI Read-Only IAM User ───────────────────────────────────────────────
# This user is for external BI tools (Power BI, Tableau, etc.)
# Read-only access to Athena, S3 processed/curated zones, and Glue catalog

resource "aws_iam_user" "powerbi_reader" {
  name = "${var.project_name}-powerbi-reader"
  tags = {
    Purpose = "Power BI / External BI tool read-only access"
    Project = var.project_name
  }
}

resource "aws_iam_access_key" "powerbi_reader" {
  user = aws_iam_user.powerbi_reader.name
}

# Store access keys in Secrets Manager so they're never exposed in plain text
resource "aws_secretsmanager_secret" "powerbi_credentials" {
  name                    = "${var.project_name}/powerbi-reader-credentials"
  description             = "Access keys for Power BI read-only IAM user"
  kms_key_id              = aws_kms_key.data.arn
  recovery_window_in_days = 7
}

resource "aws_secretsmanager_secret_version" "powerbi_credentials" {
  secret_id = aws_secretsmanager_secret.powerbi_credentials.id
  secret_string = jsonencode({
    access_key_id      = aws_iam_access_key.powerbi_reader.id
    secret_access_key  = aws_iam_access_key.powerbi_reader.secret
    region             = var.aws_region
    athena_workgroup   = "${var.project_name}-workgroup"
    s3_output_location = "s3://${var.bucket_name}/${var.athena_results_prefix}"
  })
}

# Read-only policy — Athena queries + S3 read + Glue catalog read
resource "aws_iam_policy" "powerbi_readonly" {
  name        = "${var.project_name}-powerbi-readonly"
  description = "Read-only policy for Power BI / external BI tools"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AthenaQueryAccess"
        Effect = "Allow"
        Action = [
          "athena:StartQueryExecution",
          "athena:GetQueryExecution",
          "athena:GetQueryResults",
          "athena:StopQueryExecution",
          "athena:GetWorkGroup",
          "athena:ListWorkGroups",
          "athena:ListDatabases",
          "athena:ListTableMetadata",
          "athena:GetTableMetadata",
          "athena:GetDatabase"
        ]
        Resource = "*"
      },
      {
        Sid    = "GlueCatalogReadOnly"
        Effect = "Allow"
        Action = [
          "glue:GetDatabase",
          "glue:GetDatabases",
          "glue:GetTable",
          "glue:GetTables",
          "glue:GetPartition",
          "glue:GetPartitions",
          "glue:BatchGetPartition"
        ]
        Resource = "*"
      },
      {
        Sid    = "S3ReadProcessedAndCurated"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = [
          "arn:aws:s3:::${var.bucket_name}",
          "arn:aws:s3:::${var.bucket_name}/${var.processed_prefix}*",
          "arn:aws:s3:::${var.bucket_name}/${var.curated_prefix}*",
          "arn:aws:s3:::${var.bucket_name}/${var.athena_results_prefix}*"
        ]
      },
      {
        Sid    = "S3AthenaResultsWrite"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject"
        ]
        Resource = "arn:aws:s3:::${var.bucket_name}/${var.athena_results_prefix}*"
      },
      {
        Sid    = "KMSDecryptForReading"
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey",
          "kms:DescribeKey"
        ]
        Resource = aws_kms_key.data.arn
      },
      {
        Sid    = "DenyRawZone"
        Effect = "Deny"
        Action = "s3:*"
        Resource = [
          "arn:aws:s3:::${var.bucket_name}/${var.raw_prefix}*"
        ]
      }
    ]
  })
}

resource "aws_iam_user_policy_attachment" "powerbi_readonly" {
  user       = aws_iam_user.powerbi_reader.name
  policy_arn = aws_iam_policy.powerbi_readonly.arn
}
