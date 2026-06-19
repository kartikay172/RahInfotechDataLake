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
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
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
          ArnLike = { "kms:EncryptionContext:aws:logs:arn" = "arn:aws:logs:ap-south-1:${data.aws_caller_identity.current.account_id}:*" }
        }
      }
    ]
  })
}

resource "aws_kms_alias" "data" {
  name          = "alias/${var.project_name}-key"
  target_key_id = aws_kms_key.data.key_id
}