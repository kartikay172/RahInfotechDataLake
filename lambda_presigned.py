import json
import boto3
import os
from datetime import datetime

s3 = boto3.client('s3', region_name='ap-south-1')

BUCKET = os.environ.get('BUCKET_NAME', 'navkirat-sharepoint-datalake-v2')
PREFIX = os.environ.get('RAW_PREFIX', 'raw/')
EXPIRY = 300  # 5 minutes

def lambda_handler(event, context):
    try:
        # Get filename from query params or body
        params = event.get('queryStringParameters') or {}
        body   = json.loads(event.get('body') or '{}')
        
        filename    = params.get('filename') or body.get('filename')
        folder      = params.get('folder')   or body.get('folder', '')
        content_type = params.get('content_type') or body.get('content_type', 'application/octet-stream')
        
        if not filename:
            return {
                'statusCode': 400,
                'headers': {'Access-Control-Allow-Origin': '*'},
                'body': json.dumps({'error': 'filename is required'})
            }
        
        # Build S3 key with date partitioning
        now = datetime.utcnow()
        if folder:
            folder = folder.strip('/')
            key = f"{PREFIX}{folder}/{filename}"
        else:
            key = f"{PREFIX}{filename}"
        
        # Generate presigned PUT URL
        presigned_url = s3.generate_presigned_url(
            'put_object',
            Params={
                'Bucket': BUCKET,
                'Key': key,
                'ContentType': content_type,
                'ServerSideEncryption': 'aws:kms'
            },
            ExpiresIn=EXPIRY
        )
        
        return {
            'statusCode': 200,
            'headers': {
                'Access-Control-Allow-Origin': '*',
                'Content-Type': 'application/json'
            },
            'body': json.dumps({
                'upload_url': presigned_url,
                'bucket': BUCKET,
                's3_key': key,
                'expires_in_seconds': EXPIRY,
                'message': f'Upload your file to upload_url using HTTP PUT'
            })
        }
        
    except Exception as e:
        return {
            'statusCode': 500,
            'headers': {'Access-Control-Allow-Origin': '*'},
            'body': json.dumps({'error': str(e)})
        }
