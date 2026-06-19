resource "aws_s3_bucket" "data" {
  bucket = var.bucket_name
}

resource "aws_s3_bucket_versioning" "data" {
  bucket = aws_s3_bucket.data.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "data" {
  bucket = aws_s3_bucket.data.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.data.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "data" {
  bucket                  = aws_s3_bucket.data.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "appflow_write" {
  bucket = aws_s3_bucket.data.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowAppFlowWrite"
      Effect    = "Allow"
      Principal = { Service = "appflow.amazonaws.com" }
      Action    = ["s3:PutObject", "s3:GetBucketAcl", "s3:PutObjectAcl"]
      Resource  = [aws_s3_bucket.data.arn, "${aws_s3_bucket.data.arn}/*"]
      Condition = { StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id } }
    }]
  })
}

resource "aws_s3_bucket_lifecycle_configuration" "backup_archive" {
  bucket = aws_s3_bucket.data.id
  rule {
    id     = "sharepoint-backup-tiering"
    status = "Enabled"
    filter { prefix = var.sharepoint_backup_prefix }
    transition {
      days          = var.backup_glacier_transition_days
      storage_class = "GLACIER_IR"
    }
  }
}