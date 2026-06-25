# ── Lambda IAM Role ───────────────────────────────────────────────────────────
resource "aws_iam_role" "lambda_presigned" {
  name = "${var.project_name}-lambda-presigned-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "lambda_presigned" {
  name = "${var.project_name}-lambda-presigned-policy"
  role = aws_iam_role.lambda_presigned.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3PutObject"
        Effect = "Allow"
        Action = ["s3:PutObject", "s3:GetObject"]
        Resource = "arn:aws:s3:::${var.bucket_name}/${var.raw_prefix}*"
      },
      {
        Sid    = "KMSEncrypt"
        Effect = "Allow"
        Action = ["kms:GenerateDataKey", "kms:Decrypt", "kms:DescribeKey"]
        Resource = aws_kms_key.data.arn
      },
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# ── Lambda Function ───────────────────────────────────────────────────────────
data "archive_file" "lambda_presigned" {
  type        = "zip"
  source_file = "${path.module}/lambda_presigned.py"
  output_path = "${path.module}/lambda_presigned.zip"
}

resource "aws_lambda_function" "presigned_url" {
  filename         = data.archive_file.lambda_presigned.output_path
  function_name    = "${var.project_name}-presigned-url"
  role             = aws_iam_role.lambda_presigned.arn
  handler          = "lambda_presigned.lambda_handler"
  runtime          = "python3.11"
  timeout          = 30
  source_code_hash = data.archive_file.lambda_presigned.output_base64sha256

  environment {
    variables = {
      BUCKET_NAME = var.bucket_name
      RAW_PREFIX  = var.raw_prefix
    }
  }
}

# ── API Gateway ───────────────────────────────────────────────────────────────
resource "aws_api_gateway_rest_api" "presigned" {
  name        = "${var.project_name}-presigned-api"
  description = "API to generate presigned S3 URLs for SharePoint sync"
}

resource "aws_api_gateway_resource" "upload" {
  rest_api_id = aws_api_gateway_rest_api.presigned.id
  parent_id   = aws_api_gateway_rest_api.presigned.root_resource_id
  path_part   = "upload"
}

resource "aws_api_gateway_method" "upload_post" {
  rest_api_id   = aws_api_gateway_rest_api.presigned.id
  resource_id   = aws_api_gateway_resource.upload.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "upload_lambda" {
  rest_api_id             = aws_api_gateway_rest_api.presigned.id
  resource_id             = aws_api_gateway_resource.upload.id
  http_method             = aws_api_gateway_method.upload_post.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.presigned_url.invoke_arn
}

resource "aws_api_gateway_deployment" "presigned" {
  rest_api_id = aws_api_gateway_rest_api.presigned.id
  depends_on  = [aws_api_gateway_integration.upload_lambda]
  stage_name  = "prod"
}

resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.presigned_url.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.presigned.execution_arn}/*/*"
}

output "presigned_api_url" {
  value       = "${aws_api_gateway_deployment.presigned.invoke_url}/upload"
  description = "Use this URL in Power Automate to get presigned S3 upload URL"
}
