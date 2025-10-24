output "website_url" {
  description = "Website URL (CloudFront or S3)"
  value       = var.enable_cloudfront ? "https://${aws_cloudfront_distribution.website[0].domain_name}" : "http://${aws_s3_bucket_website_configuration.website.website_endpoint}"
}

output "api_gateway_url" {
  description = "API Gateway endpoint URL"
  value       = aws_apigatewayv2_stage.main.invoke_url
}

output "api_key" {
  description = "API Gateway API key (sensitive)"
  value       = aws_apigatewayv2_api_key.main.value
  sensitive   = true
}

output "upload_bucket_name" {
  description = "S3 upload bucket name"
  value       = aws_s3_bucket.upload.id
}

output "clean_bucket_name" {
  description = "S3 clean files bucket name"
  value       = aws_s3_bucket.clean.id
}

output "quarantine_bucket_name" {
  description = "S3 quarantine bucket name"
  value       = aws_s3_bucket.quarantine.id
}

output "website_bucket_name" {
  description = "S3 website bucket name"
  value       = aws_s3_bucket.website.id
}

output "cloudwatch_dashboard_url" {
  description = "CloudWatch Dashboard URL"
  value       = "https://console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.main.dashboard_name}"
}

output "sns_success_topic_arn" {
  description = "SNS topic ARN for success notifications"
  value       = aws_sns_topic.success.arn
}

output "sns_alert_topic_arn" {
  description = "SNS topic ARN for security alerts"
  value       = aws_sns_topic.alert.arn
}

output "kms_key_id" {
  description = "KMS key ID used for encryption"
  value       = aws_kms_key.main.id
}

output "upload_handler_function_name" {
  description = "Upload handler Lambda function name"
  value       = aws_lambda_function.upload_handler.function_name
}

output "scanner_function_name" {
  description = "Malware scanner Lambda function name"
  value       = aws_lambda_function.scanner.function_name
}

output "deployment_instructions" {
  description = "Next steps after deployment"
  value       = <<-EOT
    Deployment Complete! 🎉
    
    Next Steps:
    1. Update frontend/upload.js with the API Gateway URL:
       API_ENDPOINT = '${aws_apigatewayv2_stage.main.invoke_url}'
       API_KEY = '${aws_apigatewayv2_api_key.main.value}'
    
    2. Deploy frontend to S3:
       aws s3 sync ../frontend s3://${aws_s3_bucket.website.id}
    
    3. Access your application:
       ${var.enable_cloudfront ? "https://${aws_cloudfront_distribution.website[0].domain_name}" : "http://${aws_s3_bucket_website_configuration.website.website_endpoint}"}
    
    4. Test file upload with:
       curl -X POST '${aws_apigatewayv2_stage.main.invoke_url}/get-upload-url' \
         -H 'x-api-key: ${aws_apigatewayv2_api_key.main.value}' \
         -H 'Content-Type: application/json' \
         -d '{"filename": "test.pdf", "contentType": "application/pdf"}'
    
    5. Monitor your deployment:
       CloudWatch Dashboard: https://console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.main.dashboard_name}
    
    Security Notes:
    - Store the API key securely (shown above)
    - SNS subscriptions require email confirmation
    - Check CloudWatch Logs for any deployment issues
  EOT
}
