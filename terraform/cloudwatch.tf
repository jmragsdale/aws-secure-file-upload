# CloudWatch Dashboard
resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${var.project_name}-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/Lambda", "Invocations", { stat = "Sum", label = "Upload Handler Invocations" }],
            [".", ".", "FunctionName", aws_lambda_function.scanner.function_name, { stat = "Sum", label = "Scanner Invocations" }],
            [".", "Errors", "FunctionName", aws_lambda_function.upload_handler.function_name, { stat = "Sum", label = "Upload Handler Errors" }],
            [".", ".", "FunctionName", aws_lambda_function.scanner.function_name, { stat = "Sum", label = "Scanner Errors" }]
          ]
          period = 300
          stat   = "Sum"
          region = var.aws_region
          title  = "Lambda Function Metrics"
        }
      },
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/Lambda", "Duration", "FunctionName", aws_lambda_function.upload_handler.function_name, { stat = "Average" }],
            [".", ".", ".", aws_lambda_function.scanner.function_name, { stat = "Average" }]
          ]
          period = 300
          stat   = "Average"
          region = var.aws_region
          title  = "Lambda Duration (ms)"
        }
      },
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/S3", "NumberOfObjects", "BucketName", aws_s3_bucket.upload.id, "StorageType", "AllStorageTypes", { stat = "Average", label = "Upload Bucket" }],
            [".", ".", ".", aws_s3_bucket.clean.id, ".", ".", { stat = "Average", label = "Clean Bucket" }],
            [".", ".", ".", aws_s3_bucket.quarantine.id, ".", ".", { stat = "Average", label = "Quarantine Bucket" }]
          ]
          period = 86400
          stat   = "Average"
          region = var.aws_region
          title  = "S3 Object Counts"
        }
      },
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/ApiGateway", "Count", "ApiId", aws_apigatewayv2_api.main.id, { stat = "Sum", label = "Total Requests" }],
            [".", "4XXError", ".", ".", { stat = "Sum", label = "4XX Errors" }],
            [".", "5XXError", ".", ".", { stat = "Sum", label = "5XX Errors" }]
          ]
          period = 300
          stat   = "Sum"
          region = var.aws_region
          title  = "API Gateway Metrics"
        }
      },
      {
        type = "log"
        properties = {
          query   = "SOURCE '${aws_cloudwatch_log_group.scanner.name}'\n| fields @timestamp, @message\n| filter @message like /MALWARE DETECTED/\n| sort @timestamp desc\n| limit 20"
          region  = var.aws_region
          title   = "Recent Malware Detections"
          stacked = false
        }
      }
    ]
  })
}

# CloudWatch Alarm - High Error Rate (Upload Handler)
resource "aws_cloudwatch_metric_alarm" "upload_handler_errors" {
  alarm_name          = "${var.project_name}-upload-handler-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = 5
  alarm_description   = "This metric monitors upload handler errors"
  alarm_actions       = [aws_sns_topic.alert.arn]

  dimensions = {
    FunctionName = aws_lambda_function.upload_handler.function_name
  }

  tags = {
    Name = "${var.project_name}-upload-handler-errors"
  }
}

# CloudWatch Alarm - High Error Rate (Scanner)
resource "aws_cloudwatch_metric_alarm" "scanner_errors" {
  alarm_name          = "${var.project_name}-scanner-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = 5
  alarm_description   = "This metric monitors scanner errors"
  alarm_actions       = [aws_sns_topic.alert.arn]

  dimensions = {
    FunctionName = aws_lambda_function.scanner.function_name
  }

  tags = {
    Name = "${var.project_name}-scanner-errors"
  }
}

# CloudWatch Alarm - Lambda Throttling
resource "aws_cloudwatch_metric_alarm" "upload_handler_throttles" {
  alarm_name          = "${var.project_name}-upload-handler-throttles"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Throttles"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = 10
  alarm_description   = "This metric monitors upload handler throttling"
  alarm_actions       = [aws_sns_topic.alert.arn]

  dimensions = {
    FunctionName = aws_lambda_function.upload_handler.function_name
  }

  tags = {
    Name = "${var.project_name}-upload-handler-throttles"
  }
}

# CloudWatch Alarm - API Gateway 5XX Errors
resource "aws_cloudwatch_metric_alarm" "api_gateway_5xx" {
  alarm_name          = "${var.project_name}-api-5xx-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "5XXError"
  namespace           = "AWS/ApiGateway"
  period              = 300
  statistic           = "Sum"
  threshold           = 10
  alarm_description   = "This metric monitors API Gateway 5XX errors"
  alarm_actions       = [aws_sns_topic.alert.arn]

  dimensions = {
    ApiId = aws_apigatewayv2_api.main.id
  }

  tags = {
    Name = "${var.project_name}-api-5xx-errors"
  }
}

# CloudWatch Alarm - Scanner Duration (timeout warning)
resource "aws_cloudwatch_metric_alarm" "scanner_duration" {
  alarm_name          = "${var.project_name}-scanner-duration"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "Duration"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Average"
  threshold           = var.lambda_timeout * 1000 * 0.8 # 80% of timeout
  alarm_description   = "Scanner function approaching timeout"
  alarm_actions       = [aws_sns_topic.alert.arn]

  dimensions = {
    FunctionName = aws_lambda_function.scanner.function_name
  }

  tags = {
    Name = "${var.project_name}-scanner-duration"
  }
}

# CloudWatch Metric Filter - Malware Detection
resource "aws_cloudwatch_log_metric_filter" "malware_detected" {
  name           = "${var.project_name}-malware-detected"
  log_group_name = aws_cloudwatch_log_group.scanner.name
  pattern        = "[time, request_id, level = ERROR, msg = \"*MALWARE DETECTED*\"]"

  metric_transformation {
    name      = "MalwareDetected"
    namespace = "${var.project_name}/Security"
    value     = "1"
  }
}

# CloudWatch Alarm - Malware Detection
resource "aws_cloudwatch_metric_alarm" "malware_detected" {
  alarm_name          = "${var.project_name}-malware-detected"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "MalwareDetected"
  namespace           = "${var.project_name}/Security"
  period              = 60
  statistic           = "Sum"
  threshold           = 1
  alarm_description   = "Malware has been detected in an uploaded file"
  alarm_actions       = [aws_sns_topic.alert.arn]
  treat_missing_data  = "notBreaching"

  tags = {
    Name = "${var.project_name}-malware-detected"
  }
}

# CloudWatch Insights Query Definitions
resource "aws_cloudwatch_query_definition" "scanner_performance" {
  name = "${var.project_name}/scanner-performance"

  log_group_names = [
    aws_cloudwatch_log_group.scanner.name
  ]

  query_string = <<-QUERY
    fields @timestamp, @duration, @message
    | filter @type = "REPORT"
    | stats avg(@duration), max(@duration), min(@duration) by bin(5m)
  QUERY
}

resource "aws_cloudwatch_query_definition" "failed_scans" {
  name = "${var.project_name}/failed-scans"

  log_group_names = [
    aws_cloudwatch_log_group.scanner.name
  ]

  query_string = <<-QUERY
    fields @timestamp, @message
    | filter @message like /ERROR/ or @message like /FAILED/
    | sort @timestamp desc
    | limit 50
  QUERY
}

resource "aws_cloudwatch_query_definition" "malware_detections" {
  name = "${var.project_name}/malware-detections"

  log_group_names = [
    aws_cloudwatch_log_group.scanner.name
  ]

  query_string = <<-QUERY
    fields @timestamp, @message
    | filter @message like /MALWARE DETECTED/
    | parse @message /.*file: (?<filename>[^ ]*).*/
    | sort @timestamp desc
    | limit 100
  QUERY
}
