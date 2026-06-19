variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "ap-south-1"
}

variable "project_name" {
  description = "Short name used to prefix all resources"
  type        = string
  default     = "sharepoint-data"
}

variable "bucket_name" {
  description = "Globally unique S3 bucket name"
  type        = string
}

variable "raw_data_prefix" {
  type    = string
  default = "raw-data/"
}

variable "athena_results_prefix" {
  type    = string
  default = "athena-results/"
}

variable "glue_database_name" {
  type    = string
  default = "sharepoint_db"
}

variable "sharepoint_backup_prefix" {
  type    = string
  default = "sharepoint-backup/"
}

variable "backup_glacier_transition_days" {
  type    = number
  default = 90
}

variable "pii_salt" {
  description = "Salt used for PII hashing - stored in Secrets Manager"
  type        = string
  sensitive   = true
  default     = "rah-infotech-pii-salt-2026"
}