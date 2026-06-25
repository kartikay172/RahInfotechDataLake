resource "aws_secretsmanager_secret" "pii_config" {
  name                    = "${var.project_name}/pii-config"
  description             = "PII salt and config for SharePoint ETL pipeline"
  kms_key_id              = aws_kms_key.data.arn
  recovery_window_in_days = 7
}

resource "aws_secretsmanager_secret_version" "pii_config" {
  secret_id = aws_secretsmanager_secret.pii_config.id
  secret_string = jsonencode({
    pii_salt = var.pii_salt
  })
}