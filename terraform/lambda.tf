# Data source for Lambda function code
data "archive_file" "upload_handler" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda-functions/upload-handler"
  output_path = "${path.module}/upload-handler.zip"
}

data "archive_file" "scanner" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda-functions/malware-scanner"
  output_path = "${path.module}/scanner.zip"
}

# Upload Handler Lambda Function
resource "aws_lambda_function" "upload_handler" {
  filename         = data.archive_file.upload_handler.output_path
  function_name    = "${var.project_name}-upload-handler"
  role             = aws_iam_role.upload_handler_role.arn
  handler          = "handler.lambda_handler"
  source_code_hash = data.archive_file.upload_handler.output_base64sha256
  runtime          = "python3.11"
  timeout          = 30
  memory_size      = 512

  environment {
    variables = {
      UPLOAD_BUCKET_NAME   = aws_s3_bucket.upload.id
      ALLOWED_FILE_TYPES   = jsonencode(var.allowed_file_types)
      MAX_FILE_SIZE_BYTES  = var.max_file_size_mb * 1024 * 1024
      PRESIGNED_URL_EXPIRY = var.presigned_url_expiration
      KMS_KEY_ID           = aws_kms_key.main.id
    }
  }

  dynamic "vpc_config" {
    for_each = var.enable_vpc ? [1] : []
    content {
      subnet_ids         = aws_subnet.private[*].id
      security_group_ids = [aws_security_group.lambda[0].id]
    }
  }

  tags = {
    Name = "${var.project_name}-upload-handler"
  }

  depends_on = [
    aws_cloudwatch_log_group.upload_handler,
    aws_iam_role_policy.upload_handler_policy
  ]
}

# Scanner Lambda Function
resource "aws_lambda_function" "scanner" {
  filename         = data.archive_file.scanner.output_path
  function_name    = "${var.project_name}-scanner"
  role             = aws_iam_role.scanner_role.arn
  handler          = "scanner.lambda_handler"
  source_code_hash = data.archive_file.scanner.output_base64sha256
  runtime          = "python3.11"
  timeout          = var.lambda_timeout
  memory_size      = var.lambda_memory_size

  # Note: In production, add ClamAV layer
  # layers = [aws_lambda_layer_version.clamav.arn]

  environment {
    variables = {
      UPLOAD_BUCKET_NAME     = aws_s3_bucket.upload.id
      CLEAN_BUCKET_NAME      = aws_s3_bucket.clean.id
      QUARANTINE_BUCKET_NAME = aws_s3_bucket.quarantine.id
      SNS_SUCCESS_TOPIC_ARN  = aws_sns_topic.success.arn
      SNS_ALERT_TOPIC_ARN    = aws_sns_topic.alert.arn
      KMS_KEY_ID             = aws_kms_key.main.id
    }
  }

  dynamic "vpc_config" {
    for_each = var.enable_vpc ? [1] : []
    content {
      subnet_ids         = aws_subnet.private[*].id
      security_group_ids = [aws_security_group.lambda[0].id]
    }
  }

  tags = {
    Name = "${var.project_name}-scanner"
  }

  depends_on = [
    aws_cloudwatch_log_group.scanner,
    aws_iam_role_policy.scanner_policy
  ]
}

# CloudWatch Log Groups
resource "aws_cloudwatch_log_group" "upload_handler" {
  name              = "/aws/lambda/${var.project_name}-upload-handler"
  retention_in_days = var.log_retention_days

  tags = {
    Name = "${var.project_name}-upload-handler-logs"
  }
}

resource "aws_cloudwatch_log_group" "scanner" {
  name              = "/aws/lambda/${var.project_name}-scanner"
  retention_in_days = var.log_retention_days

  tags = {
    Name = "${var.project_name}-scanner-logs"
  }
}

# Lambda Permission for S3 to invoke Scanner
resource "aws_lambda_permission" "allow_s3_invoke_scanner" {
  statement_id  = "AllowExecutionFromS3"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.scanner.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.upload.arn
}

# Lambda Permission for API Gateway to invoke Upload Handler
resource "aws_lambda_permission" "allow_api_invoke_upload_handler" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.upload_handler.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.main.execution_arn}/*/*"
}

# Lambda Layer for ClamAV (placeholder - build separately)
# Uncomment and build the layer using the provided script
# resource "aws_lambda_layer_version" "clamav" {
#   filename            = "${path.module}/../lambda-layers/clamav-layer.zip"
#   layer_name          = "${var.project_name}-clamav"
#   compatible_runtimes = ["python3.11"]
#   description         = "ClamAV antivirus engine and virus definitions"
# }

# Lambda Function URLs (optional - for direct testing)
resource "aws_lambda_function_url" "upload_handler" {
  function_name      = aws_lambda_function.upload_handler.function_name
  authorization_type = "NONE" # Use API Gateway for auth instead

  cors {
    allow_credentials = false
    allow_origins     = ["*"]
    allow_methods     = ["POST"]
    allow_headers     = ["*"]
    max_age           = 86400
  }
}
