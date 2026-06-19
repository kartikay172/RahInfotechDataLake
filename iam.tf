resource "aws_iam_role" "appflow_s3" {
  name = "${var.project_name}-appflow-s3-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "appflow.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
}

resource "aws_iam_role_policy" "appflow_s3" {
  name = "${var.project_name}-appflow-s3-policy"
  role = aws_iam_role.appflow_s3.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = ["s3:PutObject","s3:GetBucketAcl","s3:PutObjectAcl","s3:ListBucket"], Resource = [aws_s3_bucket.data.arn, "${aws_s3_bucket.data.arn}/*"] }]
  })
}

resource "aws_iam_role" "glue_crawler" {
  name = "${var.project_name}-glue-crawler-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "glue.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
}

resource "aws_iam_role_policy_attachment" "glue_service" {
  role       = aws_iam_role.glue_crawler.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

resource "aws_iam_role_policy" "glue_s3_read" {
  name = "${var.project_name}-glue-s3-read"
  role = aws_iam_role.glue_crawler.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3Access"
        Effect = "Allow"
        Action = ["s3:GetObject","s3:PutObject","s3:DeleteObject","s3:ListBucket"]
        Resource = [aws_s3_bucket.data.arn, "${aws_s3_bucket.data.arn}/*"]
      },
      {
        Sid    = "KMSAccess"
        Effect = "Allow"
        Action = ["kms:Decrypt","kms:GenerateDataKey","kms:DescribeKey","kms:Encrypt","kms:ReEncrypt*","kms:CreateGrant","kms:ListGrants"]
        Resource = [aws_kms_key.data.arn]
      },
      {
        Sid    = "SecretsManagerAccess"
        Effect = "Allow"
        Action = ["secretsmanager:GetSecretValue","secretsmanager:DescribeSecret"]
        Resource = [aws_secretsmanager_secret.pii_config.arn]
      },
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:AssociateKmsKey",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

resource "aws_iam_policy" "athena_query" {
  name = "${var.project_name}-athena-query-policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["athena:StartQueryExecution","athena:GetQueryExecution","athena:GetQueryResults","athena:StopQueryExecution","athena:GetWorkGroup"], Resource = "*" },
      { Effect = "Allow", Action = ["glue:GetDatabase","glue:GetTable","glue:GetTables","glue:GetPartitions"], Resource = "*" },
      { Effect = "Allow", Action = ["s3:GetObject","s3:ListBucket","s3:PutObject"], Resource = [aws_s3_bucket.data.arn, "${aws_s3_bucket.data.arn}/*"] },
      { Effect = "Allow", Action = ["kms:Decrypt","kms:GenerateDataKey"], Resource = [aws_kms_key.data.arn] }
    ]
  })
}