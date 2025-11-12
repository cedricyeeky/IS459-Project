import json
import boto3
import os
from datetime import datetime

sns = boto3.client('sns')
SNS_TOPIC_ARN = os.environ['SNS_TOPIC_ARN']

def lambda_handler(event, context):
    """
    Triggered by S3 events in DLQ bucket.
    Sends notification to SNS topic.
    """
    try:
        # Parse S3 event
        for record in event['Records']:
            bucket = record['s3']['bucket']['name']
            key = record['s3']['object']['key']
            event_time = record['eventTime']
            event_name = record['eventName']
            size = record['s3']['object']['size']
            
            # Determine error type from folder
            if 'scraping_errors/' in key:
                error_type = '🔴 Scraping Error'
            elif 'cleaning_errors/' in key:
                error_type = '🟠 Data Cleaning Error'
            elif 'feature_eng_errors/' in key:
                error_type = '🟡 Feature Engineering Error'
            elif 'lambda_errors/' in key:
                error_type = '🔵 Lambda Error'
            else:
                error_type = '⚪ Unknown Error'
            
            # Create message
            subject = f"DLQ Alert: {error_type}"
            message = f"""
🚨 New Error Logged to DLQ

Error Type: {error_type}
File: s3://{bucket}/{key}
Size: {size} bytes
Event: {event_name}
Time: {event_time}

View in AWS Console:
https://s3.console.aws.amazon.com/s3/object/{bucket}?prefix={key}

---
This is an automated alert from your Flight Delays DLQ monitoring system.
            """
            
            # Publish to SNS
            response = sns.publish(
                TopicArn=SNS_TOPIC_ARN,
                Subject=subject,
                Message=message
            )
            
            print(f"✅ Notification sent for {key}, MessageId: {response['MessageId']}")
        
        return {
            'statusCode': 200,
            'body': json.dumps('Notifications sent successfully')
        }
        
    except Exception as e:
        print(f"❌ Error sending notification: {str(e)}")
        raise
