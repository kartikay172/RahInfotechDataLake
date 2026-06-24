resource "aws_glue_catalog_table" "skill_set_of_team" {
  name          = "skill_set_of_team_sheet1"
  database_name = aws_glue_catalog_database.this.name
  description   = "Team skills from Skill_Set_of_Team.xlsx - Sheet1 (PII masked)"
  table_type    = "EXTERNAL_TABLE"

  parameters = {
    "classification"            = "csv"
    "delimiter"                 = ","
    "skip.header.line.count"    = "1"
    "projection.enabled"        = "true"
    "projection.year.type"      = "integer"
    "projection.year.range"     = "2024,2030"
    "projection.month.type"     = "integer"
    "projection.month.range"    = "01,12"
    "projection.month.digits"   = "2"
    "projection.day.type"       = "integer"
    "projection.day.range"      = "01,31"
    "projection.day.digits"     = "2"
    "storage.location.template" = "s3://${var.bucket_name}/${var.curated_prefix}Resources_Details/Skill_Set_of_Team/Sheet1/year=$${year}/month=$${month}/day=$${day}"
  }

  storage_descriptor {
    location      = "s3://${var.bucket_name}/${var.curated_prefix}Resources_Details/Skill_Set_of_Team/Sheet1/"
    input_format  = "org.apache.hadoop.mapred.TextInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat"

    ser_de_info {
      serialization_library = "org.apache.hadoop.hive.serde2.lazy.LazySimpleSerDe"
      parameters            = { "field.delim" = "," }
    }

    columns {
      name = "s_no"
      type = "string"
    }
    columns {
      name    = "names"
      type    = "string"
      comment = "PII masked"
    }
    columns {
      name = "skill_set"
      type = "string"
    }
    columns {
      name = "domain"
      type = "string"
    }
    columns {
      name    = "doj"
      type    = "string"
      comment = "PII hashed"
    }
  }

  partition_keys {
    name = "year"
    type = "string"
  }
  partition_keys {
    name = "month"
    type = "string"
  }
  partition_keys {
    name = "day"
    type = "string"
  }
}

resource "aws_glue_catalog_table" "mostly_common_services" {
  name          = "mostly_common_services_data"
  database_name = aws_glue_catalog_database.this.name
  description   = "AWS/Azure services from Mostly_Common_Services.xlsx - DATA sheet"
  table_type    = "EXTERNAL_TABLE"

  parameters = {
    "classification"            = "csv"
    "delimiter"                 = ","
    "skip.header.line.count"    = "1"
    "projection.enabled"        = "true"
    "projection.year.type"      = "integer"
    "projection.year.range"     = "2024,2030"
    "projection.month.type"     = "integer"
    "projection.month.range"    = "01,12"
    "projection.month.digits"   = "2"
    "projection.day.type"       = "integer"
    "projection.day.range"      = "01,31"
    "projection.day.digits"     = "2"
    "storage.location.template" = "s3://${var.bucket_name}/${var.curated_prefix}Services/AWS Services/Mostly_Common_Services/DATA/year=$${year}/month=$${month}/day=$${day}"
  }

  storage_descriptor {
    location      = "s3://${var.bucket_name}/${var.curated_prefix}Services/AWS Services/Mostly_Common_Services/DATA/"
    input_format  = "org.apache.hadoop.mapred.TextInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat"

    ser_de_info {
      serialization_library = "org.apache.hadoop.hive.serde2.lazy.LazySimpleSerDe"
      parameters            = { "field.delim" = "," }
    }

    columns {
      name = "category"
      type = "string"
    }
    columns {
      name = "service_name"
      type = "string"
    }
    columns {
      name = "description"
      type = "string"
    }
    columns {
      name = "use_case"
      type = "string"
    }
    columns {
      name = "tier"
      type = "string"
    }
    columns {
      name = "notes"
      type = "string"
    }
  }

  partition_keys {
    name = "year"
    type = "string"
  }
  partition_keys {
    name = "month"
    type = "string"
  }
  partition_keys {
    name = "day"
    type = "string"
  }
}