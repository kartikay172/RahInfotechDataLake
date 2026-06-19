resource "aws_athena_workgroup" "this" {
  name = "${var.project_name}-workgroup"

  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true

    result_configuration {
      output_location = "s3://${aws_s3_bucket.data.bucket}/${var.athena_results_prefix}"
    }
  }
}
