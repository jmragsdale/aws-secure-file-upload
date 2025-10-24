# 🐛 Troubleshooting Guide

Common issues and solutions for the AWS Secure File Upload System.

## 📋 Table of Contents

- [Deployment Issues](#deployment-issues)
- [Lambda Function Issues](#lambda-function-issues)
- [Upload Issues](#upload-issues)
- [Scanning Issues](#scanning-issues)
- [Monitoring Issues](#monitoring-issues)
- [Cost Issues](#cost-issues)

---

## 🚀 Deployment Issues

### Issue: `terraform apply` fails with authentication error

**Error Message:**
```
Error: error configuring Terraform AWS Provider: no valid credential sources
```

**Solution:**
```bash
# Configure AWS credentials
aws configure

# Verify credentials
aws sts get-caller-identity

# Check if correct profile is set
export AWS_PROFILE=your-profile-name
```

---

### Issue: S3 bucket name already exists

**Error Message:**
```
Error: Error creating S3 bucket: BucketAlreadyExists
```

**Solution:**
The random suffix should prevent this, but if it occurs:
```bash
# Edit terraform/variables.tf and change project_name
# Or let Terraform generate a new random suffix
terraform destroy
terraform apply
```

---

### Issue: IAM permissions denied

**Error Message:**
```
Error: AccessDenied: User is not authorized to perform: iam:CreateRole
```

**Solution:**
Ensure your AWS user has these permissions:
- IAMFullAccess
- AmazonS3FullAccess
- AWSLambdaFullAccess
- AmazonAPIGatewayAdministrator
- CloudWatchFullAccess

Or attach the `AdministratorAccess` policy (for testing only).

---

### Issue: Terraform state is locked

**Error Message:**
```
Error: Error acquiring the state lock
```

**Solution:**
```bash
# Wait a few minutes, then try again
# OR force unlock (use with caution)
terraform force-unlock LOCK_ID
```

---

### Issue: CloudFront distribution takes too long

**Symptom:** Website not loading after 10 minutes

**Solution:**
CloudFront can take 15-30 minutes to fully deploy. Either:
```bash
# Option 1: Wait longer (check AWS console for status)

# Option 2: Disable CloudFront temporarily
# In terraform.tfvars:
enable_cloudfront = false
terraform apply

# Use S3 website endpoint instead
terraform output website_url
```

---

## ⚡ Lambda Function Issues

### Issue: Lambda function timeout

**Error in CloudWatch Logs:**
```
Task timed out after 300.00 seconds
```

**Solution:**
```hcl
# In terraform/variables.tf, increase timeout
variable "lambda_timeout" {
  default = 600  # Increase to 10 minutes
}

# Then apply
terraform apply
```

---

### Issue: Lambda out of memory

**Error Message:**
```
Runtime.OutOfMemory: Lambda function ran out of memory
```

**Solution:**
```hcl
# In terraform/variables.tf, increase memory
variable "lambda_memory_size" {
  default = 3008  # Increase to 3GB
}

terraform apply
```

---

### Issue: Lambda can't access S3

**Error Message:**
```
AccessDenied: Access Denied
```

**Solution:**
Check IAM role permissions:
```bash
# View Lambda role policy
aws iam get-role-policy \
  --role-name secure-file-upload-scanner-role \
  --policy-name secure-file-upload-scanner-policy

# The role should have S3 GetObject and PutObject permissions
```

---

### Issue: Lambda has no internet access (VPC)

**Error Message:**
```
connect ETIMEDOUT
```

**Solution:**
If VPC is enabled, Lambda needs NAT Gateway for internet:
```bash
# Check if NAT Gateway exists
aws ec2 describe-nat-gateways

# Or disable VPC temporarily
# In terraform.tfvars:
enable_vpc = false
terraform apply
```

---

## 📤 Upload Issues

### Issue: Presigned URL expired

**Error Message:**
```
Request has expired
```

**Solution:**
Presigned URLs expire after 15 minutes. Request a new one:
```bash
# Get new upload URL
curl -X POST "$API_URL/get-upload-url" \
  -H "x-api-key: $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"filename": "test.pdf", "contentType": "application/pdf"}'
```

---

### Issue: File type not allowed

**Error Message:**
```
File type application/octet-stream is not allowed
```

**Solution:**
Add the content type to allowed types:
```hcl
# In terraform.tfvars
allowed_file_types = [
  "image/jpeg",
  "image/png",
  "application/pdf",
  "application/octet-stream"  # Add this
]

terraform apply
```

---

### Issue: File too large

**Error Message:**
```
File size exceeds maximum of 50MB
```

**Solution:**
Increase the limit:
```hcl
# In terraform.tfvars
max_file_size_mb = 100  # Increase to 100MB

terraform apply
```

---

### Issue: CORS error in browser

**Error in Browser Console:**
```
Access to fetch at '...' from origin '...' has been blocked by CORS policy
```

**Solution:**
Check API Gateway CORS settings:
```bash
# View current CORS config
aws apigatewayv2 get-api --api-id YOUR_API_ID

# Verify CloudFront is allowed origin
# Should include your CloudFront URL in allowed origins
```

---

### Issue: Upload fails with 403

**Error Message:**
```
403 Forbidden
```

**Solution:**
1. **Check API key:**
```javascript
// In frontend/upload.js
const CONFIG = {
    API_KEY: 'YOUR_ACTUAL_API_KEY'  // Make sure this is correct
};
```

2. **Verify API key in request:**
```bash
# Test with curl
curl -X POST "$API_URL/get-upload-url" \
  -H "x-api-key: $(terraform output -raw api_key)" \
  -H "Content-Type: application/json" \
  -d '{"filename": "test.pdf", "contentType": "application/pdf"}'
```

---

## 🔍 Scanning Issues

### Issue: Files not being scanned

**Symptom:** Files stay in upload bucket forever

**Solution:**

1. **Check S3 event notification:**
```bash
aws s3api get-bucket-notification-configuration \
  --bucket YOUR_UPLOAD_BUCKET_NAME
```

2. **Check Lambda permissions:**
```bash
aws lambda get-policy \
  --function-name secure-file-upload-scanner
```

3. **Manually test scanner:**
```bash
# Check CloudWatch logs
aws logs tail /aws/lambda/secure-file-upload-scanner --follow
```

---

### Issue: ClamAV not installed

**Error in Logs:**
```
ModuleNotFoundError: No module named 'clamav'
```

**Solution:**
The scanner function has a mock implementation for testing. For production:

1. Build the ClamAV Lambda layer:
```bash
cd lambda-layers
./build-clamav-layer.sh
```

2. Uncomment the layer in `terraform/lambda.tf`:
```hcl
resource "aws_lambda_function" "scanner" {
  # ...
  layers = [aws_lambda_layer_version.clamav.arn]  # Uncomment this
}
```

---

### Issue: Scanner keeps failing

**Error Message:**
```
Scanner execution failed
```

**Solution:**

1. **Check scanner logs:**
```bash
aws logs tail /aws/lambda/secure-file-upload-scanner \
  --follow \
  --filter-pattern "ERROR"
```

2. **Test with small file first:**
```bash
# Upload a small text file
echo "test" > test.txt
# Upload via interface
```

3. **Check memory and timeout:**
```bash
# Increase both in terraform.tfvars
lambda_memory_size = 2048
lambda_timeout = 300
```

---

## 📊 Monitoring Issues

### Issue: CloudWatch dashboard not showing data

**Symptom:** Empty graphs

**Solution:**

1. **Wait 5-10 minutes** for data to appear
2. **Verify Lambda was invoked:**
```bash
aws lambda get-function --function-name secure-file-upload-upload-handler
aws cloudwatch get-metric-statistics \
  --namespace AWS/Lambda \
  --metric-name Invocations \
  --dimensions Name=FunctionName,Value=secure-file-upload-upload-handler \
  --start-time 2024-01-01T00:00:00Z \
  --end-time 2024-12-31T23:59:59Z \
  --period 3600 \
  --statistics Sum
```

---

### Issue: Not receiving SNS emails

**Symptom:** No alert emails

**Solution:**

1. **Check email subscription:**
```bash
aws sns list-subscriptions-by-topic \
  --topic-arn $(terraform output -raw sns_alert_topic_arn)
```

2. **Confirm subscription:**
- Check your email for confirmation link
- Click to confirm subscription

3. **Test SNS manually:**
```bash
aws sns publish \
  --topic-arn $(terraform output -raw sns_alert_topic_arn) \
  --message "Test alert"
```

---

### Issue: Logs not appearing

**Symptom:** CloudWatch log group is empty

**Solution:**

1. **Check log group exists:**
```bash
aws logs describe-log-groups \
  --log-group-name-prefix /aws/lambda/secure-file-upload
```

2. **Verify IAM permissions:**
Lambda execution role needs CloudWatch Logs permissions.

3. **Force Lambda execution:**
Upload a file to trigger logs.

---

## 💰 Cost Issues

### Issue: Unexpected charges

**Symptom:** Bill higher than expected

**Solution:**

1. **Check what's running:**
```bash
# List all resources
aws resourcegroupstaggingapi get-resources \
  --tag-filters Key=Project,Values=secure-file-upload
```

2. **Common cost culprits:**
   - **NAT Gateway:** $30-45/month if enabled
   - **CloudFront:** Data transfer costs
   - **S3:** Large files stored
   - **Lambda:** Excessive invocations

3. **Reduce costs:**
```hcl
# In terraform.tfvars
enable_vpc = false         # Removes NAT Gateway
enable_cloudfront = false  # Reduces transfer costs
s3_lifecycle_days = 7      # Delete old files faster
```

---

### Issue: Free tier exceeded

**Symptom:** Charges for services that should be free

**Solution:**

1. **Check free tier usage:**
   - AWS Console → Billing → Free Tier

2. **Common free tier limits:**
   - Lambda: 1M requests/month, 400K GB-seconds
   - S3: 5GB storage, 20K GET requests
   - API Gateway: 1M requests/month (first 12 months)

3. **Stay within limits:**
   - Delete test files regularly
   - Don't run load tests
   - Use lifecycle policies

---

## 🔧 General Debugging

### View all Terraform outputs
```bash
cd terraform
terraform output
```

### View specific output
```bash
terraform output -raw api_key
terraform output website_url
```

### Check AWS resource status
```bash
# Lambda functions
aws lambda list-functions | grep secure-file-upload

# S3 buckets
aws s3 ls | grep secure-file-upload

# API Gateway
aws apigatewayv2 get-apis
```

### View CloudWatch Logs
```bash
# List log groups
aws logs describe-log-groups \
  --log-group-name-prefix /aws/lambda/secure-file-upload

# Tail logs (real-time)
aws logs tail /aws/lambda/secure-file-upload-scanner --follow

# Search logs
aws logs filter-log-events \
  --log-group-name /aws/lambda/secure-file-upload-scanner \
  --filter-pattern "ERROR"
```

### Test API endpoint
```bash
# Get API URL and key
API_URL=$(cd terraform && terraform output -raw api_gateway_url)
API_KEY=$(cd terraform && terraform output -raw api_key)

# Test endpoint
curl -X POST "$API_URL/get-upload-url" \
  -H "x-api-key: $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"filename": "test.pdf", "contentType": "application/pdf"}' \
  -v
```

### Check S3 bucket contents
```bash
# List upload bucket
aws s3 ls s3://$(cd terraform && terraform output -raw upload_bucket_name)/

# List clean bucket
aws s3 ls s3://$(cd terraform && terraform output -raw clean_bucket_name)/

# List quarantine bucket
aws s3 ls s3://$(cd terraform && terraform output -raw quarantine_bucket_name)/
```

---

## 📞 Getting More Help

### AWS Documentation
- [Lambda Troubleshooting](https://docs.aws.amazon.com/lambda/latest/dg/lambda-troubleshooting.html)
- [S3 Troubleshooting](https://docs.aws.amazon.com/AmazonS3/latest/userguide/troubleshooting.html)
- [API Gateway Troubleshooting](https://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-troubleshooting.html)

### Terraform Documentation
- [AWS Provider Docs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [Troubleshooting](https://www.terraform.io/docs/cli/commands/console.html)

### Community Support
- [AWS Forums](https://forums.aws.amazon.com/)
- [Terraform Community](https://discuss.hashicorp.com/c/terraform-core)
- Stack Overflow: Tag with `aws`, `terraform`, `aws-lambda`

---

## 🔄 Still Having Issues?

1. **Check CloudWatch Logs** - Most errors are logged here
2. **Review Terraform outputs** - Ensure all resources were created
3. **Test each component** - API, Lambda, S3 separately
4. **Simplify** - Disable VPC, CloudFront, WAF temporarily
5. **Start fresh** - `terraform destroy` then `terraform apply`

---

**Remember:** Most issues are related to:
- ✅ AWS credentials/permissions
- ✅ Timing (waiting for resources to be ready)
- ✅ Configuration (check terraform.tfvars)
- ✅ Logs (always check CloudWatch first!)

Good luck! 🚀
