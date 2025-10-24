import json
import os
import boto3
import uuid
from datetime import datetime, timedelta
from botocore.exceptions import ClientError

# Initialize AWS clients
s3_client = boto3.client('s3')

# Environment variables
UPLOAD_BUCKET = os.environ['UPLOAD_BUCKET_NAME']
ALLOWED_FILE_TYPES = json.loads(os.environ['ALLOWED_FILE_TYPES'])
MAX_FILE_SIZE = int(os.environ['MAX_FILE_SIZE_BYTES'])
PRESIGNED_URL_EXPIRY = int(os.environ['PRESIGNED_URL_EXPIRY'])
KMS_KEY_ID = os.environ['KMS_KEY_ID']

def lambda_handler(event, context):
    """
    Generate a presigned URL for secure file upload to S3
    """
    print(f"Received event: {json.dumps(event)}")
    
    try:
        # Handle different event formats (API Gateway HTTP API vs REST API)
        if 'body' in event:
            if isinstance(event['body'], str):
                body = json.loads(event['body'])
            else:
                body = event['body']
        else:
            body = event
        
        # Extract parameters
        filename = body.get('filename')
        content_type = body.get('contentType')
        file_size = body.get('fileSize', 0)
        
        # Validation
        if not filename or not content_type:
            return error_response(400, "Missing required fields: filename and contentType")
        
        # Validate file type
        if content_type not in ALLOWED_FILE_TYPES:
            return error_response(400, f"File type {content_type} is not allowed")
        
        # Validate file size
        if file_size > MAX_FILE_SIZE:
            return error_response(400, f"File size exceeds maximum of {MAX_FILE_SIZE / (1024 * 1024)}MB")
        
        # Sanitize filename
        safe_filename = sanitize_filename(filename)
        
        # Generate unique key
        file_key = f"{datetime.utcnow().strftime('%Y/%m/%d')}/{uuid.uuid4()}-{safe_filename}"
        
        # Generate presigned URL
        presigned_url = s3_client.generate_presigned_url(
            'put_object',
            Params={
                'Bucket': UPLOAD_BUCKET,
                'Key': file_key,
                'ContentType': content_type,
                'ServerSideEncryption': 'aws:kms',
                'SSEKMSKeyId': KMS_KEY_ID
            },
            ExpiresIn=PRESIGNED_URL_EXPIRY
        )
        
        print(f"Generated presigned URL for: {file_key}")
        
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'uploadUrl': presigned_url,
                'fileKey': file_key,
                'expiresIn': PRESIGNED_URL_EXPIRY,
                'message': 'Upload URL generated successfully'
            })
        }
        
    except ClientError as e:
        print(f"AWS Client Error: {str(e)}")
        return error_response(500, "Failed to generate upload URL")
    
    except Exception as e:
        print(f"Unexpected error: {str(e)}")
        return error_response(500, "Internal server error")


def sanitize_filename(filename):
    """
    Sanitize filename to prevent path traversal and other attacks
    """
    # Remove any directory paths
    filename = os.path.basename(filename)
    
    # Remove or replace dangerous characters
    dangerous_chars = ['<', '>', ':', '"', '/', '\\', '|', '?', '*', '\x00']
    for char in dangerous_chars:
        filename = filename.replace(char, '_')
    
    # Limit filename length
    max_length = 200
    if len(filename) > max_length:
        name, ext = os.path.splitext(filename)
        filename = name[:max_length - len(ext)] + ext
    
    return filename


def error_response(status_code, message):
    """
    Generate error response
    """
    return {
        'statusCode': status_code,
        'headers': {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*'
        },
        'body': json.dumps({
            'error': message
        })
    }
