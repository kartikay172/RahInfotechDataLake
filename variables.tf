variable "aws_region" {
  type    = string
  default = "ap-south-1"
}
variable "project_name" {
  type    = string
  default = "sharepoint-data"
}
variable "bucket_name" {
  type = string
}
variable "raw_prefix" {
  description = "RAW zone - original SharePoint files"
  type        = string
  default     = "raw/"
}
variable "processed_prefix" {
  description = "PROCESSED zone - cleaned PII-masked CSVs"
  type        = string
  default     = "processed/"
}
variable "curated_prefix" {
  description = "CURATED zone - business-ready tables for Athena"
  type        = string
  default     = "curated/"
}
variable "athena_results_prefix" {
  type    = string
  default = "athena-results/"
}
variable "glue_database_name" {
  type    = string
  default = "sharepoint_db"
}
variable "pii_salt" {
  type      = string
  sensitive = true
  default   = "rah-infotech-pii-salt-2026"
}