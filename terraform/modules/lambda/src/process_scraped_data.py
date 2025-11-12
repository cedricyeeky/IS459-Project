"""
Lambda function to process scraped flight and weather data.
Triggered by S3 EventBridge notifications when new JSON files are uploaded.
Cleans and validates data, then writes to Silver bucket in Parquet format.
"""

import json
import os
import boto3
import pandas as pd
from datetime import datetime
from io import BytesIO

s3 = boto3.client('s3')

# Environment variables
RAW_BUCKET = os.environ['RAW_BUCKET']
SILVER_BUCKET = os.environ['SILVER_BUCKET']
DLQ_BUCKET = os.environ['DLQ_BUCKET']


def lambda_handler(event, context):
    """
    Process S3 EventBridge notification for new scraped data files.
    """
    print(f"Received event: {json.dumps(event)}")
    
    try:
        # Extract S3 bucket and key from EventBridge event
        detail = event.get('detail', {})
        bucket_name = detail.get('bucket', {}).get('name')
        object_key = detail.get('object', {}).get('key')
        
        if not bucket_name or not object_key:
            print("ERROR: Missing bucket or key in event")
            return {
                'statusCode': 400,
                'body': json.dumps('Invalid event structure')
            }
        
        print(f"Processing file: s3://{bucket_name}/{object_key}")
        
        # Determine data type from path
        if 'scraped/weather/' in object_key:
            data_type = 'weather'
        elif 'scraped/flights/' in object_key:
            data_type = 'flights'
        else:
            print(f"Skipping file - not in flights or weather folder: {object_key}")
            return {
                'statusCode': 200,
                'body': json.dumps('File skipped - not in target folders')
            }
        
        # Extract filename without extension
        filename = object_key.split('/')[-1].replace('.json', '')
        
        # Download and process the file
        response = s3.get_object(Bucket=bucket_name, Key=object_key)
        file_content = response['Body'].read().decode('utf-8')
        
        # Parse JSON
        data = json.loads(file_content)
        
        # Extract the data array from the response structure
        if isinstance(data, dict):
            if data_type == 'weather' and 'observations' in data:
                # Weather data: extract observations array
                records = data['observations']
            elif data_type == 'flights' and 'flights' in data:
                # Flights data: extract flights array
                records = data['flights']
            elif 'data' in data:
                # Fallback: check for generic 'data' key
                records = data['data']
            else:
                # If dict doesn't have expected keys, treat whole dict as single record
                records = [data]
        elif isinstance(data, list):
            # Already an array
            records = data
        else:
            raise ValueError(f"Unexpected data format: {type(data)}")
        
        # Convert to DataFrame
        df = pd.DataFrame(records)
        
        if df.empty:
            print(f"WARNING: Empty data in {object_key}")
            return {
                'statusCode': 200,
                'body': json.dumps('Empty data file')
            }
        
        # Clean and validate data based on type
        try:
            if data_type == 'weather':
                df = clean_weather_data(df, filename)
            elif data_type == 'flights':
                df = clean_flight_data(df, filename)
        except Exception as cleaning_error:
            print(f"ERROR during data cleaning: {str(cleaning_error)}")
            
            # Save failed data to DLQ
            error_key = f"cleaning_errors/{data_type}/{datetime.utcnow().strftime('%Y%m%d_%H%M%S')}_{filename}.json"
            s3.put_object(
                Bucket=DLQ_BUCKET,
                Key=error_key,
                Body=json.dumps({
                    'error': str(cleaning_error),
                    'error_type': 'cleaning_failed',
                    'data_type': data_type,
                    'source_file': object_key,
                    'raw_data': data,
                    'timestamp': datetime.utcnow().isoformat()
                }, default=str)
            )
            print(f"Failed cleaning data saved to DLQ: s3://{DLQ_BUCKET}/{error_key}")
            
            raise cleaning_error
        
        # Write to Silver bucket
        output_key = f"scraped/{data_type}/{filename}_cleaned.snappy.parquet"
        write_to_silver(df, output_key)
        
        print(f"Successfully processed {len(df)} records to s3://{SILVER_BUCKET}/{output_key}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Success',
                'records_processed': len(df),
                'output': f"s3://{SILVER_BUCKET}/{output_key}"
            })
        }
        
    except Exception as e:
        print(f"ERROR: {str(e)}")
        
        # Write error to DLQ
        try:
            error_key = f"lambda_errors/{datetime.utcnow().strftime('%Y%m%d_%H%M%S')}_{object_key.replace('/', '_')}.json"
            s3.put_object(
                Bucket=DLQ_BUCKET,
                Key=error_key,
                Body=json.dumps({
                    'error': str(e),
                    'event': event,
                    'timestamp': datetime.utcnow().isoformat()
                })
            )
            print(f"Error logged to DLQ: s3://{DLQ_BUCKET}/{error_key}")
        except Exception as dlq_error:
            print(f"Failed to write to DLQ: {str(dlq_error)}")
        
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error: {str(e)}')
        }


def clean_weather_data(df, source_filename):
    """
    Clean and validate weather data.
    """
    print(f"Cleaning weather data: {len(df)} records")
    
    # Add metadata
    df['source_file'] = source_filename
    df['processed_at'] = datetime.utcnow().isoformat()
    
    # Remove duplicates based on key fields
    if 'obs_id' in df.columns and 'valid_time_gmt' in df.columns:
        before = len(df)
        df = df.drop_duplicates(subset=['obs_id', 'valid_time_gmt'], keep='last')
        after = len(df)
        if before != after:
            print(f"Removed {before - after} duplicate weather records")
    
    # Basic validation - remove records with missing critical fields
    required_fields = ['obs_id', 'valid_time_gmt']
    for field in required_fields:
        if field in df.columns:
            before = len(df)
            df = df[df[field].notna()]
            after = len(df)
            if before != after:
                print(f"Removed {before - after} records with missing {field}")
    
    # Convert numeric fields
    numeric_fields = ['temp', 'wspd', 'vis', 'precip_hrly', 'snow_hrly']
    for field in numeric_fields:
        if field in df.columns:
            df[field] = pd.to_numeric(df[field], errors='coerce')
    
    return df


def clean_flight_data(df, source_filename):
    """
    Clean and validate flight data.
    """
    print(f"Cleaning flight data: {len(df)} records")
    
    # Add metadata
    df['source_file'] = source_filename
    df['processed_at'] = datetime.utcnow().isoformat()
    
    # Remove duplicates based on key fields
    id_fields = ['flight_id'] if 'flight_id' in df.columns else ['carrier_code', 'flight_number', 'flight_date']
    if all(field in df.columns for field in id_fields):
        before = len(df)
        df = df.drop_duplicates(subset=id_fields, keep='last')
        after = len(df)
        if before != after:
            print(f"Removed {before - after} duplicate flight records")
    
    # Basic validation
    required_fields = ['carrier_code', 'origin_airport', 'destination_airport']
    for field in required_fields:
        if field in df.columns:
            before = len(df)
            df = df[df[field].notna()]
            after = len(df)
            if before != after:
                print(f"Removed {before - after} records with missing {field}")
    
    # Convert numeric fields
    numeric_fields = ['arrival_delay_minutes', 'departure_delay_minutes']
    for field in numeric_fields:
        if field in df.columns:
            df[field] = pd.to_numeric(df[field], errors='coerce')
    
    # Convert boolean fields
    boolean_fields = ['on_time', 'is_delayed', 'is_cancelled', 'cascade_risk']
    for field in boolean_fields:
        if field in df.columns:
            df[field] = df[field].astype(bool)
    
    return df


def write_to_silver(df, output_key):
    """
    Write DataFrame to Silver bucket in Parquet format.
    """
    print(f"Writing to s3://{SILVER_BUCKET}/{output_key}")
    
    # Convert to Parquet in memory
    parquet_buffer = BytesIO()
    df.to_parquet(parquet_buffer, engine='pyarrow', compression='snappy', index=False)
    
    # Upload to S3
    s3.put_object(
        Bucket=SILVER_BUCKET,
        Key=output_key,
        Body=parquet_buffer.getvalue(),
        ContentType='application/x-parquet'
    )
    
    print(f"Successfully wrote {len(df)} records to Silver bucket")
