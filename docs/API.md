# 📡 API Documentation

Complete API documentation for the AWS Secure File Upload System.

## 📋 Table of Contents

- [Overview](#overview)
- [Authentication](#authentication)
- [Endpoints](#endpoints)
- [Error Codes](#error-codes)
- [Rate Limits](#rate-limits)
- [Examples](#examples)

---

## 🌐 Overview

**Base URL:** `https://YOUR_API_ID.execute-api.REGION.amazonaws.com/prod`

**Protocol:** HTTPS only
**Format:** JSON
**Authentication:** API Key (x-api-key header)

Get your API URL:
```bash
cd terraform
terraform output api_gateway_url
```

---

## 🔐 Authentication

All API requests require an API key in the request header.

### Getting Your API Key

```bash
# Get API key (keep this secure!)
terraform output -raw api_key
```

### Using the API Key

```bash
curl -X POST "https://API_URL/get-upload-url" \
  -H "x-api-key: YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"filename": "test.pdf", "contentType": "application/pdf"}'
```

### Security Notes

- ⚠️ **Keep your API key secret**
- 🔄 Rotate keys regularly
- 🚫 Never commit keys to version control
- 📝 Log API key usage

---

## 🔌 Endpoints

### 1. Get Upload URL

Generate a presigned URL for uploading a file to S3.

**Endpoint:** `POST /get-upload-url`

#### Request

**Headers:**
```
x-api-key: YOUR_API_KEY
Content-Type: application/json
```

**Body:**
```json
{
  "filename": "example.pdf",
  "contentType": "application/pdf",
  "fileSize": 1048576
}
```

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| filename | string | Yes | Original filename |
| contentType | string | Yes | MIME type of file |
| fileSize | number | No | File size in bytes |

**Allowed Content Types:**
- `image/jpeg`
- `image/png`
- `image/gif`
- `application/pdf`
- `application/msword`
- `application/vnd.openxmlformats-officedocument.wordprocessingml.document`
- `application/zip`

#### Response

**Success (200 OK):**
```json
{
  "uploadUrl": "https://bucket.s3.amazonaws.com/path?X-Amz-Algorithm=...",
  "fileKey": "2024/01/15/uuid-example.pdf",
  "expiresIn": 900,
  "message": "Upload URL generated successfully"
}
```

**Response Fields:**

| Field | Type | Description |
|-------|------|-------------|
| uploadUrl | string | Presigned S3 URL for upload |
| fileKey | string | S3 object key |
| expiresIn | number | URL expiration (seconds) |
| message | string | Success message |

**Error (400 Bad Request):**
```json
{
  "error": "File type application/exe is not allowed"
}
```

**Error (401 Unauthorized):**
```json
{
  "message": "Unauthorized"
}
```

#### Example

```bash
API_URL="https://abc123.execute-api.us-east-1.amazonaws.com/prod"
API_KEY="your-api-key-here"

curl -X POST "$API_URL/get-upload-url" \
  -H "x-api-key: $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "filename": "document.pdf",
    "contentType": "application/pdf",
    "fileSize": 2097152
  }'
```

---

### 2. Upload File to S3

After getting the presigned URL, upload the file directly to S3.

**Endpoint:** The `uploadUrl` returned from step 1

#### Request

**Method:** `PUT`

**Headers:**
```
Content-Type: [same as contentType from step 1]
```

**Body:** Binary file data

#### Response

**Success (200 OK):**
Empty response body

**Error (403 Forbidden):**
URL expired or invalid

#### Example

```bash
# Get upload URL first
RESPONSE=$(curl -s -X POST "$API_URL/get-upload-url" \
  -H "x-api-key: $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"filename": "test.pdf", "contentType": "application/pdf"}')

# Extract upload URL
UPLOAD_URL=$(echo $RESPONSE | jq -r '.uploadUrl')

# Upload file
curl -X PUT "$UPLOAD_URL" \
  --upload-file test.pdf \
  -H "Content-Type: application/pdf"
```

---

### 3. Health Check

Check API availability (no authentication required).

**Endpoint:** `GET /health`

#### Request

**Headers:** None required

#### Response

**Success (200 OK):**
```json
{
  "status": "healthy",
  "timestamp": "2024-01-15T10:30:00Z"
}
```

#### Example

```bash
curl -X GET "$API_URL/health"
```

---

## ⚠️ Error Codes

### HTTP Status Codes

| Code | Meaning | Description |
|------|---------|-------------|
| 200 | OK | Request successful |
| 400 | Bad Request | Invalid parameters |
| 401 | Unauthorized | Invalid API key |
| 403 | Forbidden | Access denied |
| 429 | Too Many Requests | Rate limit exceeded |
| 500 | Internal Server Error | Server error |
| 503 | Service Unavailable | Service temporarily down |

### Error Response Format

```json
{
  "error": "Error message describing the issue"
}
```

### Common Errors

#### File Type Not Allowed

```json
{
  "error": "File type application/exe is not allowed"
}
```

**Solution:** Use an allowed content type

#### File Too Large

```json
{
  "error": "File size exceeds maximum of 50MB"
}
```

**Solution:** Reduce file size or contact admin

#### Missing Required Fields

```json
{
  "error": "Missing required fields: filename and contentType"
}
```

**Solution:** Include all required fields

#### Invalid API Key

```json
{
  "message": "Unauthorized"
}
```

**Solution:** Check API key is correct

---

## 🚦 Rate Limits

### API Gateway Limits

- **Per API Key:** 100 requests per 5 minutes
- **Burst:** 100 concurrent requests
- **Daily:** 10,000 requests

### WAF Limits

- **Per IP:** 100 requests per 5 minutes
- **Automatic blocking:** 1 hour for violations

### S3 Upload Limits

- **Max File Size:** 50 MB (configurable)
- **Concurrent Uploads:** Unlimited
- **Presigned URL Expiry:** 15 minutes

### Rate Limit Headers

Response includes rate limit info:

```
X-RateLimit-Limit: 100
X-RateLimit-Remaining: 95
X-RateLimit-Reset: 1642245600
```

### Handling Rate Limits

**When rate limited (429):**

```json
{
  "error": "Rate limit exceeded. Try again in 5 minutes."
}
```

**Best practices:**
- Implement exponential backoff
- Cache responses when possible
- Batch operations
- Monitor usage

---

## 💡 Examples

### Example 1: Complete Upload Flow (JavaScript)

```javascript
async function uploadFile(file) {
  const API_URL = 'https://YOUR_API_ID.execute-api.REGION.amazonaws.com/prod';
  const API_KEY = 'YOUR_API_KEY';
  
  try {
    // Step 1: Get presigned URL
    const response = await fetch(`${API_URL}/get-upload-url`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': API_KEY
      },
      body: JSON.stringify({
        filename: file.name,
        contentType: file.type,
        fileSize: file.size
      })
    });
    
    if (!response.ok) {
      const error = await response.json();
      throw new Error(error.error);
    }
    
    const data = await response.json();
    const uploadUrl = data.uploadUrl;
    
    // Step 2: Upload to S3
    const uploadResponse = await fetch(uploadUrl, {
      method: 'PUT',
      headers: {
        'Content-Type': file.type
      },
      body: file
    });
    
    if (!uploadResponse.ok) {
      throw new Error('Upload failed');
    }
    
    console.log('Upload successful!');
    console.log('File will be scanned for malware...');
    
  } catch (error) {
    console.error('Upload error:', error);
  }
}
```

### Example 2: Upload with Progress (Python)

```python
import requests
import json

API_URL = 'https://YOUR_API_ID.execute-api.REGION.amazonaws.com/prod'
API_KEY = 'YOUR_API_KEY'

def upload_file(file_path):
    # Read file
    with open(file_path, 'rb') as f:
        file_data = f.read()
    
    filename = file_path.split('/')[-1]
    content_type = 'application/pdf'  # Adjust based on file
    
    # Step 1: Get presigned URL
    response = requests.post(
        f'{API_URL}/get-upload-url',
        headers={
            'x-api-key': API_KEY,
            'Content-Type': 'application/json'
        },
        json={
            'filename': filename,
            'contentType': content_type,
            'fileSize': len(file_data)
        }
    )
    
    if response.status_code != 200:
        print(f'Error: {response.json()}')
        return
    
    upload_url = response.json()['uploadUrl']
    
    # Step 2: Upload to S3
    upload_response = requests.put(
        upload_url,
        headers={'Content-Type': content_type},
        data=file_data
    )
    
    if upload_response.status_code == 200:
        print('✅ Upload successful!')
        print('🔍 File is being scanned for malware...')
    else:
        print(f'❌ Upload failed: {upload_response.status_code}')

# Usage
upload_file('document.pdf')
```

### Example 3: Batch Upload (Bash)

```bash
#!/bin/bash

API_URL="https://YOUR_API_ID.execute-api.REGION.amazonaws.com/prod"
API_KEY="YOUR_API_KEY"

# Upload multiple files
for file in *.pdf; do
    echo "Uploading $file..."
    
    # Get upload URL
    RESPONSE=$(curl -s -X POST "$API_URL/get-upload-url" \
        -H "x-api-key: $API_KEY" \
        -H "Content-Type: application/json" \
        -d "{\"filename\": \"$file\", \"contentType\": \"application/pdf\"}")
    
    UPLOAD_URL=$(echo $RESPONSE | jq -r '.uploadUrl')
    
    if [ "$UPLOAD_URL" == "null" ]; then
        echo "Error getting upload URL for $file"
        continue
    fi
    
    # Upload file
    curl -X PUT "$UPLOAD_URL" \
        --upload-file "$file" \
        -H "Content-Type: application/pdf"
    
    echo "✅ $file uploaded"
    sleep 1  # Rate limiting
done

echo "All files uploaded!"
```

### Example 4: Error Handling (Node.js)

```javascript
const axios = require('axios');
const fs = require('fs');

const API_URL = 'https://YOUR_API_ID.execute-api.REGION.amazonaws.com/prod';
const API_KEY = 'YOUR_API_KEY';

async function uploadWithRetry(filePath, maxRetries = 3) {
  const file = fs.readFileSync(filePath);
  const filename = filePath.split('/').pop();
  const contentType = 'application/pdf';
  
  for (let attempt = 1; attempt <= maxRetries; attempt++) {
    try {
      // Get presigned URL
      const { data } = await axios.post(
        `${API_URL}/get-upload-url`,
        {
          filename,
          contentType,
          fileSize: file.length
        },
        {
          headers: {
            'x-api-key': API_KEY,
            'Content-Type': 'application/json'
          }
        }
      );
      
      // Upload to S3
      await axios.put(data.uploadUrl, file, {
        headers: {
          'Content-Type': contentType
        }
      });
      
      console.log(`✅ Upload successful after ${attempt} attempt(s)`);
      return true;
      
    } catch (error) {
      console.error(`❌ Attempt ${attempt} failed:`, error.message);
      
      if (attempt === maxRetries) {
        console.error('Max retries reached. Upload failed.');
        return false;
      }
      
      // Exponential backoff
      const delay = Math.pow(2, attempt) * 1000;
      console.log(`Retrying in ${delay}ms...`);
      await new Promise(resolve => setTimeout(resolve, delay));
    }
  }
}

// Usage
uploadWithRetry('document.pdf')
  .then(success => process.exit(success ? 0 : 1));
```

---

## 📚 Additional Resources

- **Postman Collection:** Coming soon
- **OpenAPI Spec:** Coming soon
- **SDKs:** JavaScript, Python examples above
- **WebSocket Support:** Not available

---

## 🔄 API Versioning

Current version: **v1** (prod stage)

Version is included in the URL path:
```
https://API_ID.execute-api.REGION.amazonaws.com/prod
```

Future versions will use new stage names (v2, v3, etc.)

---

## 📞 Support

- **Issues:** Check [TROUBLESHOOTING.md](TROUBLESHOOTING.md)
- **Questions:** Create GitHub issue
- **Security:** Email admin (from terraform output)

---

**Happy uploading!** 📤
