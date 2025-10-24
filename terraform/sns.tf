# SNS Topic for Success Notifications
resource "aws_sns_topic" "success" {
  name              = "${var.project_name}-success-notifications"
  display_name      = "File Upload Success Notifications"
  kms_master_key_id = aws_kms_key.main.id

  tags = {
    Name = "${var.project_name}-success"
  }
}

# SNS Topic Policy for Success
resource "aws_sns_topic_policy" "success" {
  arn = aws_sns_topic.success.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowLambdaPublish"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action   = "SNS:Publish"
        Resource = aws_sns_topic.success.arn
        Condition = {
          ArnEquals = {
            "aws:SourceArn" = aws_lambda_function.scanner.arn
          }
        }
      }
    ]
  })
}

# SNS Subscription for Success (optional - comment out if not needed)
# resource "aws_sns_topic_subscription" "success_email" {
#   topic_arn = aws_sns_topic.success.arn
#   protocol  = "email"
#   endpoint  = var.alert_email
# }

# SNS Topic for Security Alerts
resource "aws_sns_topic" "alert" {
  name              = "${var.project_name}-security-alerts"
  display_name      = "Security Alerts - Malware Detected"
  kms_master_key_id = aws_kms_key.main.id

  tags = {
    Name = "${var.project_name}-alert"
  }
}

# SNS Topic Policy for Alerts
resource "aws_sns_topic_policy" "alert" {
  arn = aws_sns_topic.alert.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowLambdaPublish"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action   = "SNS:Publish"
        Resource = aws_sns_topic.alert.arn
        Condition = {
          ArnEquals = {
            "aws:SourceArn" = aws_lambda_function.scanner.arn
          }
        }
      },
      {
        Sid    = "AllowCloudWatchPublish"
        Effect = "Allow"
        Principal = {
          Service = "cloudwatch.amazonaws.com"
        }
        Action   = "SNS:Publish"
        Resource = aws_sns_topic.alert.arn
      }
    ]
  })
}

# SNS Subscription for Security Alerts
resource "aws_sns_topic_subscription" "alert_email" {
  topic_arn = aws_sns_topic.alert.arn
  protocol  = "email"
  endpoint  = var.alert_email
}
