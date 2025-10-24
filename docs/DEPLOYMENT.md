# 🚀 Deployment Guide

Complete deployment guide for the AWS Secure File Upload System.

## 📋 Table of Contents

- [Prerequisites](#prerequisites)
- [Pre-Deployment Checklist](#pre-deployment-checklist)
- [Step-by-Step Deployment](#step-by-step-deployment)
- [Post-Deployment Configuration](#post-deployment-configuration)
- [Verification](#verification)
- [Customization](#customization)
- [Updates](#updates)
- [Rollback](#rollback)

---

## ✅ Prerequisites

### Required Tools

1. **Terraform** (>= 1.5.0)
   ```bash
   terraform --version
   # If not installed: https://www.terraform.io/downloads
   ```

2. **AWS CLI**
   ```bash
   aws --version
   # If not installed: https://aws.amazon.com/cli/
   ```

3. **Python** (>= 3.9)
   ```bash
   python3 --version
   ```

4. **Git**
   ```bash
   git --version
   ```

### AWS Requirements

- Active AWS account
- IAM user with appropriate permissions:
  - IAMFullAccess
  - AmazonS3FullAccess
  - AWSLambdaFullAccess
  - AmazonAPIGatewayAdministrator
  - CloudWatchFullAccess
  - AmazonVPCFullAccess (if using VPC)

### Cost Consideration

- Estimated cost: $5-15/month
- AWS Free Tier eligible (first 12 months)
- Set billing alerts before deploying

---

## 📝 Pre-Deployment Checklist

- [ ] AWS CLI configured (`aws configure`)
- [ ] Terraform installed and working
- [ ] Decided on AWS region
- [ ] Email address ready for alerts
- [ ] Reviewed cost estimates
- [ ] Set up billing alerts
- [ ] Read through architecture documentation

---

## 🔧 Step-by-Step Deployment

### Step 1: Clone Repository

```bash
git clone https://github.com/jmragsdale/aws-secure-file-upload.git
cd aws-secure-file-upload
```

### Step 2: Configure AWS Credentials

```bash
# Configure AWS CLI
aws configure

# Verify credentials
aws sts get-caller-identity
```

Expected output:
```json
{
    "UserId": "AIDACKCEVSQ6C2EXAMPLE",
    "Account": "123456789012",
    "Arn": "arn:aws:iam::123456789012:user/your-username"
}
```

### Step 3: Configure Terraform Variables

```bash
cd terraform

# Copy example configuration
cp terraform.tfvars.example terraform.tfvars

# Edit configuration
nano terraform.tfvars
# OR
vim terraform.tfvars
# OR use any text editor
```

**Required changes in `terraform.tfvars`:**
```hcl
# REQUIRED: Change this to your email
alert_email = "your-email@example.com"

# OPTIONAL: Customize these
aws_region       = "us-east-1"  # Choose your preferred region
project_name     = "secure-file-upload"
environment      = "prod"
max_file_size_mb = 50

# Feature toggles (optional)
enable_cloudfront = true   # Set to false to reduce costs
enable_vpc        = true   # Set to false to reduce costs
enable_waf        = true   # Set to false to reduce costs
```

### Step 4: Initialize Terraform

```bash
# Initialize Terraform (downloads providers)
terraform init
```

Expected output:
```
Initializing the backend...
Initializing provider plugins...
Terraform has been successfully initialized!
```

### Step 5: Review Deployment Plan

```bash
# See what will be created
terraform plan
```

Review the output carefully. You should see:
- ~50 resources to be created
- S3 buckets, Lambda functions, API Gateway, etc.
- No resources to be destroyed

### Step 6: Deploy Infrastructure

```bash
# Deploy everything
terraform apply
```

When prompted:
```
Do you want to perform these actions?
  Terraform will perform the actions described above.
  Only 'yes' will be accepted to approve.

  Enter a value: yes  # Type 'yes' and press Enter
```

**This takes approximately 10-15 minutes.**

Watch for:
- ✅ Resource creation messages
- ✅ "Apply complete!" message
- ❌ Any error messages

### Step 7: Save Deployment Outputs

```bash
# Save all outputs to a file
terraform output > ../deployment-info.txt

# View outputs
terraform output

# Save API key securely (you'll need this)
terraform output -raw api_key > ../api-key.txt
chmod 600 ../api-key.txt  # Restrict permissions
```

**Important outputs:**
- `website_url` - Your application URL
- `api_gateway_url` - API endpoint
- `api_key` - Authentication key (keep secure!)
- `cloudwatch_dashboard_url` - Monitoring dashboard

---

## ⚙️ Post-Deployment Configuration

### Step 1: Confirm SNS Subscription

1. Check your email inbox
2. Look for "AWS Notification - Subscription Confirmation"
3. Click the confirmation link
4. You should see "Subscription confirmed!"

### Step 2: Configure Frontend

```bash
cd ../frontend

# Edit upload.js with your favorite editor
nano upload.js
```

Update these lines:
```javascript
const CONFIG = {
    API_ENDPOINT: 'https://YOUR_API_ID.execute-api.us-east-1.amazonaws.com/prod',  // From terraform output
    API_KEY: 'YOUR_API_KEY_HERE',  // From terraform output (sensitive!)
    // ... rest stays the same
};
```

To get the values:
```bash
cd ../terraform
echo "API_ENDPOINT: $(terraform output -raw api_gateway_url)"
echo "API_KEY: $(terraform output -raw api_key)"
```

### Step 3: Deploy Frontend to S3

```bash
cd ../frontend

# Get bucket name
BUCKET_NAME=$(cd ../terraform && terraform output -raw website_bucket_name)

# Deploy frontend
aws s3 sync . s3://$BUCKET_NAME/ --exclude "*.md"

# Verify upload
aws s3 ls s3://$BUCKET_NAME/
```

### Step 4: Get Website URL

```bash
cd ../terraform
terraform output website_url
```

Visit this URL in your browser!

---

## ✅ Verification

### 1. Access Website

```bash
# Get URL
terraform output website_url

# Open in browser or use curl
curl -I $(terraform output -raw website_url)
```

Expected: HTTP 200 OK

### 2. Test API Endpoint

```bash
API_URL=$(terraform output -raw api_gateway_url)
API_KEY=$(terraform output -raw api_key)

curl -X POST "$API_URL/get-upload-url" \
  -H "x-api-key: $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"filename": "test.pdf", "contentType": "application/pdf"}'
```

Expected: JSON response with `uploadUrl`

### 3. Test File Upload

1. Visit your website URL
2. Drag and drop a small file (e.g., text file, small image)
3. Watch the upload progress
4. Check for "Complete" status

### 4. Verify File Scanning

```bash
# Wait 30 seconds after upload, then check clean bucket
CLEAN_BUCKET=$(terraform output -raw clean_bucket_name)
aws s3 ls s3://$CLEAN_BUCKET/ --recursive
```

You should see your uploaded file!

### 5. Test Malware Detection

```bash
# Download EICAR test file (safe test virus)
curl -o eicar.txt https://secure.eicar.org/eicar.com.txt

# Upload via your web interface
# Expected: File quarantined, alert email received
```

Check quarantine bucket:
```bash
QUARANTINE_BUCKET=$(terraform output -raw quarantine_bucket_name)
aws s3 ls s3://$QUARANTINE_BUCKET/ --recursive
```

### 6. Check CloudWatch Logs

```bash
# View upload handler logs
aws logs tail /aws/lambda/secure-file-upload-upload-handler --follow

# View scanner logs
aws logs tail /aws/lambda/secure-file-upload-scanner --follow
```

### 7. Access Monitoring Dashboard

```bash
terraform output cloudwatch_dashboard_url
```

Open this URL to see your monitoring dashboard.

---

## 🎨 Customization

### Change File Size Limit

```hcl
# In terraform.tfvars
max_file_size_mb = 100  # Increase to 100MB
```

```bash
terraform apply
```

### Add More File Types

```hcl
# In terraform.tfvars
allowed_file_types = [
  "image/jpeg",
  "image/png",
  "application/pdf",
  "text/plain",           # Add text files
  "application/zip",       # Add zip files
  "video/mp4"             # Add video files
]
```

```bash
terraform apply
```

### Reduce Costs

```hcl
# In terraform.tfvars
enable_cloudfront = false  # Save ~$1-2/month
enable_vpc        = false  # Save ~$30/month (NAT Gateway)
enable_waf        = false  # Save ~$0.50/month
```

```bash
terraform apply
```

### Change AWS Region

```hcl
# In terraform.tfvars
aws_region = "us-west-2"  # Or any other region
```

```bash
# IMPORTANT: This will recreate everything!
terraform destroy
terraform apply
```

### Enable/Disable Features

```hcl
# In terraform.tfvars
enable_s3_versioning = true   # Keep file versions
log_retention_days   = 90     # Keep logs longer
s3_lifecycle_days    = 7      # Delete quarantine files faster
```

```bash
terraform apply
```

---

## 🔄 Updates

### Update Infrastructure

```bash
cd terraform

# Make changes to .tf files or terraform.tfvars

# Review changes
terraform plan

# Apply updates
terraform apply
```

### Update Frontend

```bash
cd frontend

# Make changes to HTML/CSS/JS

# Redeploy
BUCKET_NAME=$(cd ../terraform && terraform output -raw website_bucket_name)
aws s3 sync . s3://$BUCKET_NAME/ --exclude "*.md"
```

### Update Lambda Functions

```bash
cd lambda-functions

# Make changes to Python code

# Redeploy
cd ../terraform
terraform apply  # This will repackage and update Lambda
```

---

## ↩️ Rollback

### Rollback Last Change

```bash
cd terraform

# View state backup
ls terraform.tfstate.backup

# Restore previous state
cp terraform.tfstate.backup terraform.tfstate

# Apply previous configuration
terraform apply
```

### Complete Rollback

```bash
# Use Git to restore previous version
git log --oneline
git checkout COMMIT_HASH

# Reapply
terraform apply
```

---

## 🧹 Cleanup / Destroy

### Prepare for Destruction

```bash
cd terraform

# Empty all S3 buckets first (Terraform can't delete non-empty buckets)
aws s3 rm s3://$(terraform output -raw upload_bucket_name)/ --recursive
aws s3 rm s3://$(terraform output -raw clean_bucket_name)/ --recursive
aws s3 rm s3://$(terraform output -raw quarantine_bucket_name)/ --recursive
aws s3 rm s3://$(terraform output -raw website_bucket_name)/ --recursive

# Empty logs bucket
LOGS_BUCKET=$(aws s3 ls | grep secure-file-upload-logs | awk '{print $3}')
aws s3 rm s3://$LOGS_BUCKET/ --recursive
```

### Destroy Infrastructure

```bash
# Review what will be destroyed
terraform plan -destroy

# Destroy everything
terraform destroy
```

When prompted:
```
Do you really want to destroy all resources?
  Enter a value: yes
```

**This takes approximately 5-10 minutes.**

### Verify Cleanup

```bash
# Check for remaining resources
aws s3 ls | grep secure-file-upload
aws lambda list-functions | grep secure-file-upload
aws apigatewayv2 get-apis | grep secure-file-upload

# If anything remains, delete manually:
aws s3 rb s3://BUCKET_NAME --force
aws lambda delete-function --function-name FUNCTION_NAME
```

---

## 📊 Deployment Checklist

Use this checklist to track your deployment:

**Pre-Deployment:**
- [ ] AWS CLI configured
- [ ] Terraform installed
- [ ] Configuration file created
- [ ] Billing alerts set

**Deployment:**
- [ ] `terraform init` successful
- [ ] `terraform plan` reviewed
- [ ] `terraform apply` successful
- [ ] Outputs saved

**Configuration:**
- [ ] SNS subscription confirmed
- [ ] Frontend configured with API details
- [ ] Frontend deployed to S3
- [ ] Website accessible

**Verification:**
- [ ] Test file uploaded successfully
- [ ] File appears in clean bucket
- [ ] EICAR test quarantined
- [ ] Alert email received
- [ ] CloudWatch dashboard accessible
- [ ] Logs visible

**Documentation:**
- [ ] API key saved securely
- [ ] Website URL bookmarked
- [ ] Screenshots captured
- [ ] Issues documented

---

## 🎯 Deployment Timeline

| Phase | Duration | Description |
|-------|----------|-------------|
| **Setup** | 10 min | Install tools, configure AWS |
| **Configuration** | 5 min | Edit terraform.tfvars |
| **Infrastructure** | 10-15 min | terraform apply |
| **Frontend** | 5 min | Configure and deploy |
| **Testing** | 10 min | Upload files, verify scanning |
| **Total** | **40-45 min** | First-time deployment |

Subsequent deployments: ~5-10 minutes (updates only)

---

## 📞 Need Help?

- **Errors during deployment:** Check [TROUBLESHOOTING.md](TROUBLESHOOTING.md)
- **Understanding architecture:** Check main [README.md](../README.md)
- **Quick commands:** Check [QUICK-REFERENCE.md](../QUICK-REFERENCE.md)

---

**Congratulations on your deployment!** 🎉

Your secure file upload system is now live and ready to use!
