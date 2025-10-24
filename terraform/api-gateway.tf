# HTTP API Gateway
resource "aws_apigatewayv2_api" "main" {
  name          = "${var.project_name}-api"
  protocol_type = "HTTP"
  description   = "Secure File Upload API"

  cors_configuration {
    allow_origins = var.enable_cloudfront ? [
      "https://${aws_cloudfront_distribution.website[0].domain_name}"
    ] : ["*"]
    allow_methods = ["GET", "POST", "OPTIONS"]
    allow_headers = ["*"]
    max_age       = 300
  }

  tags = {
    Name = "${var.project_name}-api"
  }
}

# API Gateway Stage
resource "aws_apigatewayv2_stage" "main" {
  api_id      = aws_apigatewayv2_api.main.id
  name        = var.environment
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gateway.arn
    format = jsonencode({
      requestId      = "$context.requestId"
      ip             = "$context.identity.sourceIp"
      requestTime    = "$context.requestTime"
      httpMethod     = "$context.httpMethod"
      routeKey       = "$context.routeKey"
      status         = "$context.status"
      protocol       = "$context.protocol"
      responseLength = "$context.responseLength"
      errorMessage   = "$context.error.message"
    })
  }

  default_route_settings {
    throttling_burst_limit = 100
    throttling_rate_limit  = 50
  }

  tags = {
    Name = "${var.project_name}-api-stage"
  }

  depends_on = [aws_cloudwatch_log_group.api_gateway]
}

# CloudWatch Log Group for API Gateway
resource "aws_cloudwatch_log_group" "api_gateway" {
  name              = "/aws/apigateway/${var.project_name}"
  retention_in_days = var.log_retention_days

  tags = {
    Name = "${var.project_name}-api-gateway-logs"
  }
}

# Lambda Integration
resource "aws_apigatewayv2_integration" "upload_handler" {
  api_id                 = aws_apigatewayv2_api.main.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.upload_handler.invoke_arn
  integration_method     = "POST"
  payload_format_version = "2.0"
  timeout_milliseconds   = 30000
}

# API Route for getting presigned URL
resource "aws_apigatewayv2_route" "get_upload_url" {
  api_id    = aws_apigatewayv2_api.main.id
  route_key = "POST /get-upload-url"
  target    = "integrations/${aws_apigatewayv2_integration.upload_handler.id}"

  authorization_type = "CUSTOM"
  authorizer_id      = aws_apigatewayv2_authorizer.api_key.id
}

# API Route for health check
resource "aws_apigatewayv2_route" "health" {
  api_id    = aws_apigatewayv2_api.main.id
  route_key = "GET /health"
  target    = "integrations/${aws_apigatewayv2_integration.upload_handler.id}"
}

# Custom Authorizer for API Key validation
resource "aws_apigatewayv2_authorizer" "api_key" {
  api_id           = aws_apigatewayv2_api.main.id
  authorizer_type  = "REQUEST"
  identity_sources = ["$request.header.x-api-key"]
  name             = "${var.project_name}-api-key-authorizer"

  authorizer_uri                    = aws_lambda_function.api_key_authorizer.invoke_arn
  authorizer_payload_format_version = "2.0"
  enable_simple_responses           = true
}

# Lambda Authorizer Function
data "archive_file" "api_key_authorizer" {
  type        = "zip"
  output_path = "${path.module}/api-key-authorizer.zip"

  source {
    content  = <<-EOT
      import json
      import os
      
      def lambda_handler(event, context):
          api_key = event.get('headers', {}).get('x-api-key', '')
          expected_key = os.environ.get('API_KEY')
          
          is_authorized = api_key == expected_key
          
          return {
              'isAuthorized': is_authorized
          }
    EOT
    filename = "authorizer.py"
  }
}

resource "aws_lambda_function" "api_key_authorizer" {
  filename         = data.archive_file.api_key_authorizer.output_path
  function_name    = "${var.project_name}-api-key-authorizer"
  role             = aws_iam_role.api_key_authorizer_role.arn
  handler          = "authorizer.lambda_handler"
  source_code_hash = data.archive_file.api_key_authorizer.output_base64sha256
  runtime          = "python3.11"
  timeout          = 10

  environment {
    variables = {
      API_KEY = aws_apigatewayv2_api_key.main.value
    }
  }

  tags = {
    Name = "${var.project_name}-api-key-authorizer"
  }
}

# IAM Role for API Key Authorizer
resource "aws_iam_role" "api_key_authorizer_role" {
  name = "${var.project_name}-api-key-authorizer-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "api_key_authorizer_logs" {
  role       = aws_iam_role.api_key_authorizer_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Lambda Permission for API Gateway to invoke Authorizer
resource "aws_lambda_permission" "allow_api_invoke_authorizer" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api_key_authorizer.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.main.execution_arn}/*/*"
}

# API Key
resource "random_password" "api_key" {
  length  = 32
  special = false
}

resource "aws_apigatewayv2_api_key" "main" {
  name    = "${var.project_name}-api-key"
  enabled = true
}

# Store API Key in SSM Parameter Store
resource "aws_ssm_parameter" "api_key" {
  name        = "/${var.project_name}/api-key"
  description = "API Gateway API Key"
  type        = "SecureString"
  value       = random_password.api_key.result

  tags = {
    Name = "${var.project_name}-api-key"
  }
}
