resource "aws_kms_key" "data" {
  description             = "KMS key for SharePoint data lake encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow Glue Role"
        Effect = "Allow"
        Principal = { AWS = aws_iam_role.glue_crawler.arn }
        Action   = ["kms:Decrypt","kms:GenerateDataKey","kms:DescribeKey","kms:Encrypt","kms:ReEncrypt*","kms:CreateGrant"]
        Resource = "*"
      },
      {
        Sid    = "Allow CloudWatch Logs"
        Effect = "Allow"
        Principal = { Service = "logs.ap-south-1.amazonaws.com" }
        Action   = ["kms:Encrypt","kms:Decrypt","kms:ReEncrypt*","kms:GenerateDataKey","kms:DescribeKey"]
        Resource = "*"
        Condition = {
          ArnLike = {
            "kms:EncryptionContext:aws:logs:arn" = "arn:aws:logs:ap-south-1:${data.aws_caller_identity.current.account_id}:*"
          }
        }
      }
    ]
  })

  tags = {
    Name    = "${var.project_name}-kms-key"
    Project = var.project_name
  }
}

resource "aws_kms_alias" "data" {
  name          = "alias/${var.project_name}-key"
  target_key_id = aws_kms_key.data.key_id
}

# Grant Glue role access to old KMS key (eba2b72c) used for existing raw files
resource "aws_kms_grant" "glue_old_key" {
  name              = "glue-role-old-key-access"
  key_id            = "eba2b72c-f11c-4d37-bce6-eff77e7af3d8"
  grantee_principal = aws_iam_role.glue_crawler.arn
  operations        = ["Decrypt", "GenerateDataKey", "DescribeKey"]
}