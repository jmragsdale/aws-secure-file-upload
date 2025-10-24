# 🔒 Security Architecture

Comprehensive security documentation for the AWS Secure File Upload System.

## 📋 Table of Contents

- [Security Overview](#security-overview)
- [Security Features](#security-features)
- [Threat Model](#threat-model)
- [Security Best Practices](#security-best-practices)
- [Compliance](#compliance)
- [Incident Response](#incident-response)

---

## 🛡️ Security Overview

This system implements a **defense-in-depth** security strategy with multiple layers of protection:

1. **Encryption** - Data protected at rest and in transit
2. **Access Control** - Least privilege IAM policies
3. **Network Security** - VPC isolation and WAF protection
4. **Threat Detection** - Automated malware scanning
5. **Monitoring** - Comprehensive logging and alerting
6. **Input Validation** - Multiple validation layers

---

## 🔐 Security Features

### 1. Encryption

#### At Rest
- **S3 Buckets:** Encrypted with AWS KMS customer-managed keys
- **KMS Key Policy:** Restricts access to authorized services only
- **Key Rotation:** Automatic key rotation enabled
- **Encryption Algorithm:** AES-256

**Implementation:**
```hcl
# All S3 buckets use KMS encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "main" {
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.main.arn
    }
  }
}
```

#### In Transit
- **TLS 1.2+:** Enforced for all connections
- **HTTPS Only:** All HTTP traffic redirected
- **Certificate Management:** Handled by AWS
- **Strong Cipher Suites:** Only secure ciphers allowed

**Implementation:**
```hcl
# S3 bucket policy enforces HTTPS
{
  "Effect": "Deny",
  "Principal": "*",
  "Action": "s3:*",
  "Resource": "arn:aws:s3:::bucket/*",
  "Condition": {
    "Bool": {
      "aws:SecureTransport": "false"
    }
  }
}
```

### 2. Access Control

#### IAM Policies (Least Privilege)

**Upload Handler Lambda:**
- ✅ PutObject to upload bucket only
- ✅ GenerateDataKey from KMS
- ❌ No read access to other buckets
- ❌ No delete permissions

**Scanner Lambda:**
- ✅ GetObject from upload bucket
- ✅ PutObject to clean/quarantine buckets
- ✅ DeleteObject from upload bucket (cleanup)
- ✅ Publish to SNS topics
- ❌ No access to website bucket
- ❌ No IAM permissions

**Example Policy:**
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:GetObject"],
      "Resource": "arn:aws:s3:::upload-bucket/*"
    },
    {
      "Effect": "Allow",
      "Action": ["s3:PutObject"],
      "Resource": [
        "arn:aws:s3:::clean-bucket/*",
        "arn:aws:s3:::quarantine-bucket/*"
      ]
    }
  ]
}
```

#### API Authentication

**API Gateway:**
- Custom Lambda authorizer validates API keys
- Rate limiting prevents brute force
- Keys stored in SSM Parameter Store (encrypted)
- Time-limited presigned URLs (15 minutes)

**Authentication Flow:**
```
1. User requests upload URL with API key
2. Lambda authorizer validates key
3. If valid: Generate presigned S3 URL
4. User uploads directly to S3
5. S3 trigger invokes scanner
```

### 3. Network Security

#### VPC Configuration

**Isolation:**
- Lambda functions in private subnets
- No direct internet access
- NAT Gateway for outbound traffic only
- Security groups with minimal rules

**Network Diagram:**
```
Internet
    ↓
Internet Gateway
    ↓
NAT Gateway (Public Subnet)
    ↓
Lambda Functions (Private Subnet)
    ↓
VPC Endpoints (S3, etc.)
```

**Security Groups:**
```hcl
# Lambda Security Group
resource "aws_security_group" "lambda" {
  # Egress only (no ingress)
  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS for AWS services"
  }
  
  egress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP for ClamAV updates"
  }
}
```

#### WAF Protection

**Rules Implemented:**
1. **Rate Limiting:** 100 requests per IP per 5 minutes
2. **Known Bad IPs:** AWS managed threat intelligence
3. **SQL Injection:** AWS managed rule set
4. **XSS Protection:** AWS managed rule set
5. **Common Vulnerabilities:** AWS core rule set

**WAF Configuration:**
```hcl
# Rate limit rule
rule {
  rate_based_statement {
    limit              = 100
    aggregate_key_type = "IP"
  }
}
```

### 4. Threat Detection

#### Malware Scanning

**ClamAV Engine:**
- Open-source antivirus
- Updated virus definitions
- Scans every uploaded file
- Zero-day threat protection

**Scanning Process:**
```
1. File uploaded to S3
2. S3 event triggers scanner Lambda
3. Lambda downloads file
4. ClamAV scans file
5. Clean → Move to clean bucket
6. Infected → Move to quarantine, send alert
7. Delete from upload bucket
```

**Detection Capabilities:**
- ✅ Known malware signatures
- ✅ Suspicious file patterns
- ✅ Encrypted/obfuscated malware
- ✅ EICAR test file

#### Quarantine Process

When malware is detected:
1. File immediately moved to quarantine bucket
2. Quarantine bucket has restrictive access
3. Security team notified via SNS
4. Original file deleted from upload bucket
5. Event logged with full details

### 5. Monitoring & Logging

#### Comprehensive Logging

**CloudTrail:**
- All API calls logged
- Who, what, when, where
- Immutable audit trail
- Integrated with CloudWatch

**CloudWatch Logs:**
- Lambda execution logs
- API Gateway access logs
- Error tracking
- Performance metrics

**S3 Access Logs:**
- All bucket access logged
- Source IP addresses
- Request types
- Response codes

**Log Retention:**
- CloudWatch: 30 days (configurable)
- S3 Access Logs: 30 days with lifecycle
- CloudTrail: 90 days minimum

#### Real-Time Alerting

**SNS Notifications for:**
- ✅ Malware detected
- ✅ Lambda errors
- ✅ High error rates
- ✅ API throttling
- ✅ Unusual access patterns

**CloudWatch Alarms:**
- Lambda execution failures
- API Gateway 5xx errors
- Scanner timeouts
- Cost anomalies

### 6. Input Validation

#### Multiple Validation Layers

**Layer 1: Frontend (Client-Side)**
```javascript
// File type validation
if (!ALLOWED_TYPES.includes(file.type)) {
  reject("File type not allowed");
}

// File size validation
if (file.size > MAX_FILE_SIZE) {
  reject("File too large");
}

// Filename sanitization
const safeName = sanitizeFilename(file.name);
```

**Layer 2: Upload Handler Lambda**
```python
# Validate content type
if content_type not in ALLOWED_FILE_TYPES:
    return error_response(400, "File type not allowed")

# Validate file size
if file_size > MAX_FILE_SIZE:
    return error_response(400, "File too large")

# Sanitize filename
safe_filename = sanitize_filename(filename)
```

**Layer 3: S3 Bucket Policy**
```json
{
  "Condition": {
    "NumericLessThanEquals": {
      "s3:content-length": 52428800
    }
  }
}
```

**Layer 4: Malware Scanner**
```python
# Scan file contents
is_clean = scan_file(file_path)

if not is_clean:
    quarantine_file()
```

---

## 🎯 Threat Model

### Threats Addressed

| Threat | Mitigation |
|--------|-----------|
| **Malware Upload** | ClamAV scanning + quarantine |
| **Data Breach** | KMS encryption + IAM policies |
| **DDoS Attack** | WAF rate limiting + CloudFront |
| **Unauthorized Access** | API key authentication + IAM |
| **Man-in-the-Middle** | TLS 1.2+ encryption |
| **SQL Injection** | WAF rules (no database used) |
| **XSS Attacks** | WAF rules + CSP headers |
| **Insider Threat** | Least privilege + audit logs |
| **Account Takeover** | API key rotation + monitoring |

### Attack Scenarios

#### Scenario 1: Malicious File Upload

**Attack:** User uploads malware
**Defense:**
1. File type validation rejects executables
2. If bypass: ClamAV detects malware
3. File quarantined immediately
4. Security team alerted
5. No access to clean files

#### Scenario 2: Brute Force API Key

**Attack:** Attacker tries to guess API key
**Defense:**
1. WAF rate limiting (100 req/5min)
2. API Gateway throttling
3. CloudWatch alerts on unusual patterns
4. API key rotation capability

#### Scenario 3: Data Exfiltration

**Attack:** Compromised Lambda tries to steal data
**Defense:**
1. Least privilege IAM (can't read other buckets)
2. VPC isolation (no direct internet)
3. CloudTrail logs all access
4. Encryption prevents reading stolen data

---

## ✅ Security Best Practices

### For Administrators

1. **Rotate API Keys Regularly**
   ```bash
   # Generate new API key
   aws ssm put-parameter \
     --name /secure-file-upload/api-key \
     --value "NEW_KEY_HERE" \
     --type SecureString \
     --overwrite
   ```

2. **Review CloudWatch Logs Weekly**
   ```bash
   aws logs filter-log-events \
     --log-group-name /aws/lambda/scanner \
     --filter-pattern "ERROR"
   ```

3. **Monitor Costs Daily**
   - Set up billing alerts
   - Review Cost Explorer
   - Check for anomalies

4. **Update ClamAV Definitions**
   - Automated in Lambda
   - Monitor update logs
   - Test with EICAR file monthly

5. **Review IAM Policies**
   - Use IAM Access Analyzer
   - Remove unused permissions
   - Apply least privilege

### For Developers

1. **Never Commit Secrets**
   ```bash
   # Check .gitignore includes:
   terraform.tfvars
   *.tfstate
   api-key.txt
   ```

2. **Validate All Inputs**
   - Frontend validation
   - Backend validation
   - Database validation (if added)

3. **Use Secure Coding Practices**
   - Input sanitization
   - Output encoding
   - Error handling
   - Logging (no sensitive data)

4. **Keep Dependencies Updated**
   ```bash
   # Check for outdated packages
   pip list --outdated
   
   # Update Terraform providers
   terraform init -upgrade
   ```

5. **Test Security Controls**
   - Upload EICAR file
   - Test rate limiting
   - Verify encryption
   - Check access logs

---

## 📜 Compliance

### Standards Alignment

This system aligns with:

- **NIST Cybersecurity Framework**
  - Identify: Asset inventory, risk assessment
  - Protect: Encryption, access control
  - Detect: Malware scanning, monitoring
  - Respond: Quarantine, alerts
  - Recover: Backup, restoration

- **CIS AWS Foundations Benchmark**
  - IAM best practices
  - Logging and monitoring
  - Networking security
  - Data protection

- **GDPR Considerations**
  - Data encryption
  - Access controls
  - Audit logging
  - Data retention policies

### Compliance Features

- ✅ Encryption at rest and in transit
- ✅ Access logging
- ✅ Data retention policies
- ✅ Incident response procedures
- ✅ Regular security testing

---

## 🚨 Incident Response

### Response Plan

#### 1. Detection
- CloudWatch alarms trigger
- SNS notification sent
- On-call engineer notified

#### 2. Analysis
```bash
# Check logs
aws logs tail /aws/lambda/scanner --follow

# Review quarantine
aws s3 ls s3://quarantine-bucket/

# Check CloudTrail
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=PutObject
```

#### 3. Containment
- Quarantine infected files
- Block suspicious IPs in WAF
- Rotate API keys if compromised
- Isolate affected resources

#### 4. Eradication
- Remove malware
- Patch vulnerabilities
- Update ClamAV definitions
- Review and update policies

#### 5. Recovery
- Restore from clean backups
- Verify system integrity
- Monitor for recurrence
- Update documentation

#### 6. Lessons Learned
- Document incident
- Update procedures
- Improve detection
- Train team

### Emergency Contacts

```bash
# Get security team email
terraform output alert_email

# SNS topic for alerts
terraform output sns_alert_topic_arn
```

---

## 🔍 Security Testing

### Regular Testing

**Weekly:**
- Upload EICAR test file
- Review CloudWatch logs
- Check for unusual activity

**Monthly:**
- Review IAM policies
- Update dependencies
- Test incident response
- Review access logs

**Quarterly:**
- Security audit
- Penetration testing
- Policy review
- Training updates

### Testing Malware Detection

```bash
# Download safe test virus
curl -o eicar.txt https://secure.eicar.org/eicar.com.txt

# Upload via web interface
# Expected: Quarantine + alert email

# Verify quarantine
aws s3 ls s3://$(terraform output -raw quarantine_bucket_name)/
```

---

## 📚 Security Resources

- [AWS Security Best Practices](https://aws.amazon.com/security/best-practices/)
- [OWASP Top 10](https://owasp.org/www-project-top-ten/)
- [CIS AWS Foundations Benchmark](https://www.cisecurity.org/benchmark/amazon_web_services)
- [ClamAV Documentation](https://docs.clamav.net/)

---

## 📞 Security Concerns?

Report security issues to: [alert_email from terraform output]

**Do not** create public GitHub issues for security vulnerabilities.

---

**Security is everyone's responsibility.** 🔒

Regular reviews, testing, and updates are essential to maintaining a secure system.
