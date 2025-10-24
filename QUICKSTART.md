# AWS Secure File Upload - Quick Start Guide

## Prerequisites Checklist

- [ ] AWS Account with appropriate permissions
- [ ] AWS CLI installed and configured
- [ ] Terraform >= 1.5.0 installed
- [ ] Docker installed (for building Lambda layers)
- [ ] Python 3.9+ installed
- [ ] Git installed

## Step-by-Step Deployment

### 1. Configure AWS Credentials

```bash
aws configure
# Enter your AWS Access Key ID
# Enter your AWS Secret Access Key
# Enter your default region (e.g., us-east-1)
# Enter output format (json)
```

### 2. Clone and Configure Project

```bash
cd aws-secure-file-upload/terraform
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:
```hcl
alert_email = "your-email@example.com"  # REQUIRED: Change this
aws_region  = "us-east-1"               # Optional: Change if needed
```

### 3. Initialize Terraform

```bash
terraform init
```

### 4. Review Deployment Plan

```bash
terraform plan
```

Review the resources that will be created:
- 3 S3 Buckets (upload, clean, quarantine)
- 2 Lambda Functions (upload handler, malware scanner)
- API Gateway
- CloudFront Distribution (optional)
- KMS Encryption Key
- IAM Roles and Policies
- CloudWatch Alarms
- SNS Topics
- VPC and Networking (optional)

### 5. Deploy Infrastructure

```bash
terraform apply
```

Type `yes` when prompted. Deployment takes approximately 5-10 minutes.

### 6. Save Important Outputs

```bash
# Save all outputs to a file
terraform output > ../deployment-info.txt

# View specific outputs
terraform output website_url
terraform output api_gateway_url
terraform output -raw api_key
```

### 7. Configure Frontend

Edit `frontend/upload.js`:

```javascript
const CONFIG = {
    API_ENDPOINT: 'YOUR_API_GATEWAY_URL', // From terraform output
    API_KEY: 'YOUR_API_KEY',               // From terraform output (sensitive)
    // ... rest stays the same
};
```

### 8. Deploy Frontend

```bash
cd ..
BUCKET_NAME=$(cd terraform && terraform output -raw website_bucket_name)
aws s3 sync frontend/ s3://$BUCKET_NAME/
```

### 9. Confirm SNS Subscription

Check your email for SNS subscription confirmation and click the confirm link.

### 10. Test Your Deployment

#### Get your website URL:
```bash
cd terraform
terraform output website_url
```

Visit the URL in your browser and try uploading a file!

#### Test with curl:
```bash
# Get upload URL
API_URL=$(terraform output -raw api_gateway_url)
API_KEY=$(terraform output -raw api_key)

curl -X POST "$API_URL/get-upload-url" \
  -H "x-api-key: $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"filename": "test.pdf", "contentType": "application/pdf"}'
```

## Testing Malware Detection

To test that malware detection works:

```bash
# Download EICAR test file (safe test file that looks like malware)
curl -o eicar.txt https://secure.eicar.org/eicar.com.txt

# Upload it through your web interface
# It should be quarantined and you'll receive an alert email
```

## Monitoring Your System

### CloudWatch Dashboard
```bash
# Get dashboard URL
terraform output cloudwatch_dashboard_url
```

### View Logs
```bash
# Upload handler logs
aws logs tail /aws/lambda/secure-file-upload-upload-handler --follow

# Scanner logs
aws logs tail /aws/lambda/secure-file-upload-scanner --follow
```

### Check S3 Buckets
```bash
# List clean files
aws s3 ls s3://$(terraform output -raw clean_bucket_name)/

# List quarantined files
aws s3 ls s3://$(terraform output -raw quarantine_bucket_name)/
```

## Common Issues and Solutions

### Issue: API Gateway returns 403
**Solution**: Verify API key is correctly set in frontend configuration

### Issue: Files not being scanned
**Solution**: Check Lambda scanner logs for errors:
```bash
aws logs tail /aws/lambda/secure-file-upload-scanner --follow
```

### Issue: CloudFront not serving website
**Solution**: Wait 10-15 minutes for CloudFront distribution to fully deploy

### Issue: Presigned URL expired
**Solution**: URLs expire after 15 minutes. Request a new one.

## Updating the Deployment

```bash
cd terraform

# Make changes to .tf files or variables

# Review changes
terraform plan

# Apply changes
terraform apply
```

## Cleanup / Destroy

⚠️ **WARNING**: This will delete ALL resources including uploaded files!

```bash
cd terraform

# Empty S3 buckets first (Terraform can't delete non-empty buckets)
aws s3 rm s3://$(terraform output -raw upload_bucket_name)/ --recursive
aws s3 rm s3://$(terraform output -raw clean_bucket_name)/ --recursive
aws s3 rm s3://$(terraform output -raw quarantine_bucket_name)/ --recursive
aws s3 rm s3://$(terraform output -raw website_bucket_name)/ --recursive

# Destroy infrastructure
terraform destroy
```

## Cost Optimization Tips

1. **Disable CloudFront** if not needed:
   ```hcl
   enable_cloudfront = false
   ```

2. **Disable VPC** for Lambda (reduces NAT Gateway costs):
   ```hcl
   enable_vpc = false
   ```

3. **Reduce log retention**:
   ```hcl
   log_retention_days = 7
   ```

4. **Use lifecycle policies** to move old files to Glacier (already configured)

## Security Best Practices

1. **Store API Key Securely**: Never commit API key to version control
2. **Enable MFA**: Enable MFA on your AWS account
3. **Restrict IAM Permissions**: Use least privilege principle
4. **Review CloudWatch Alarms**: Regularly check for security alerts
5. **Update ClamAV Definitions**: Keep malware definitions current
6. **Monitor Costs**: Set up AWS Budgets to avoid unexpected charges

## Getting Help

- Check CloudWatch Logs for detailed error messages
- Review Terraform state: `terraform show`
- AWS CloudTrail for API call history
- GitHub Issues: [Report issues here]

## Next Steps

- [ ] Add custom domain with Route53
- [ ] Implement user authentication with Cognito
- [ ] Add file sharing capabilities
- [ ] Create admin dashboard
- [ ] Implement file versioning
- [ ] Add email notifications for successful uploads
- [ ] Set up multi-region replication
- [ ] Implement file deduplication

---

**Need Help?** Create an issue on GitHub or check the documentation in the `docs/` folder.
