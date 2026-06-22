# ── Glue Workflow — orchestrates ETL + both crawlers in sequence ───────────────
resource "aws_glue_workflow" "sharepoint_pipeline" {
  name        = "${var.project_name}-workflow"
  description = "SharePoint Data Lake Pipeline: ETL Job -> Processed Crawler -> Curated Crawler"
}

# Trigger 1: Schedule starts the workflow 3x/day
resource "aws_glue_trigger" "workflow_schedule" {
  name          = "${var.project_name}-workflow-trigger"
  type          = "SCHEDULED"
  schedule      = "cron(30 0,6,12 * * ? *)"
  workflow_name = aws_glue_workflow.sharepoint_pipeline.name

  actions {
    job_name = aws_glue_job.sharepoint_etl.name
  }

  start_on_creation = true
}

# Trigger 2: When ETL job succeeds, start the processed crawler
resource "aws_glue_trigger" "processed_crawler_trigger" {
  name          = "${var.project_name}-processed-crawler-trigger"
  type          = "CONDITIONAL"
  workflow_name = aws_glue_workflow.sharepoint_pipeline.name

  predicate {
    conditions {
      job_name = aws_glue_job.sharepoint_etl.name
      state    = "SUCCEEDED"
    }
  }

  actions {
    crawler_name = aws_glue_crawler.processed.name
  }
}

# Trigger 3: When processed crawler succeeds, start the curated crawler
resource "aws_glue_trigger" "curated_crawler_trigger" {
  name          = "${var.project_name}-curated-crawler-trigger"
  type          = "CONDITIONAL"
  workflow_name = aws_glue_workflow.sharepoint_pipeline.name

  predicate {
    conditions {
      crawler_name = aws_glue_crawler.processed.name
      crawl_state  = "SUCCEEDED"
    }
  }

  actions {
    crawler_name = aws_glue_crawler.curated.name
  }
}