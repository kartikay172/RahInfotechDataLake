resource "aws_glue_catalog_database" "this" {
  name = var.glue_database_name
}

resource "aws_s3_object" "glue_etl_script" {
  bucket = aws_s3_bucket.data.id
  key    = "glue-scripts/sharepoint_etl.py"
  source = "${path.module}/glue_etl_script.py"
  etag   = filemd5("${path.module}/glue_etl_script.py")
}

resource "aws_glue_security_configuration" "etl" {
  name = "${var.project_name}-security-config"
  encryption_configuration {
    cloudwatch_encryption {
      cloudwatch_encryption_mode = "DISABLED"
    }
    job_bookmarks_encryption {
      job_bookmarks_encryption_mode = "CSE-KMS"
      kms_key_arn                   = aws_kms_key.data.arn
    }
    s3_encryption {
      s3_encryption_mode = "SSE-KMS"
      kms_key_arn        = aws_kms_key.data.arn
    }
  }
}

resource "aws_glue_job" "sharepoint_etl" {
  name                   = "${var.project_name}-etl-job"
  role_arn               = aws_iam_role.glue_crawler.arn
  glue_version           = "4.0"
  security_configuration = aws_glue_security_configuration.etl.name
  command {
    name            = "glueetl"
    script_location = "s3://${aws_s3_bucket.data.bucket}/glue-scripts/sharepoint_etl.py"
    python_version  = "3"
  }
  default_arguments = {
    "--job-language"                     = "python"
    "--job-bookmark-option"              = "job-bookmark-enable"
    "--SOURCE_BUCKET"                    = aws_s3_bucket.data.bucket
    "--SOURCE_PREFIX"                    = var.sharepoint_backup_prefix
    "--DEST_PREFIX"                      = "processed/"
    "--SECRET_NAME"                      = aws_secretsmanager_secret.pii_config.name
    "--REGION_NAME"                      = var.aws_region
    "--enable-continuous-cloudwatch-log" = "true"
    "--enable-metrics"                   = "true"
    "--TempDir"                          = "s3://${aws_s3_bucket.data.bucket}/glue-temp/"
  }
  number_of_workers = 2
  worker_type       = "G.1X"
  timeout           = 60
}

resource "aws_glue_trigger" "etl_schedule" {
  name     = "${var.project_name}-etl-trigger"
  type     = "SCHEDULED"
  schedule = "cron(30 0,6,12 * * ? *)"
  actions {
    job_name = aws_glue_job.sharepoint_etl.name
  }
  start_on_creation = true
}

resource "aws_glue_crawler" "sharepoint_data" {
  name          = "${var.project_name}-crawler"
  role          = aws_iam_role.glue_crawler.arn
  database_name = aws_glue_catalog_database.this.name

  s3_target {
    path       = "s3://${aws_s3_bucket.data.bucket}/processed/Resources_Details/"
    exclusions = ["**.json"]
  }

  s3_target {
    path       = "s3://${aws_s3_bucket.data.bucket}/processed/Services/"
    exclusions = ["**.json"]
  }

  schema_change_policy {
    update_behavior = "UPDATE_IN_DATABASE"
    delete_behavior = "LOG"
  }

  configuration = jsonencode({
    Version = 1.0
    CrawlerOutput = {
      Partitions = { AddOrUpdateBehavior = "InheritFromTable" }
      Tables     = { AddOrUpdateBehavior = "MergeNewColumns" }
    }
    Grouping = {
      TableGroupingPolicy = "CombineCompatibleSchemas"
    }
  })
}