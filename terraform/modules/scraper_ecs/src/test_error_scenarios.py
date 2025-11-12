#!/usr/bin/env python3
"""
DLQ Error Logging - 3 Demo Scenarios
Interactive script to demonstrate error logging with faulty responses
"""

import os
import sys
import json
from datetime import datetime

# Set environment variables
os.environ['API_ENDPOINT'] = 'http://flight-mock-api-prod-alb-2052111428.us-east-1.amazonaws.com'
os.environ['S3_BUCKET'] = 'flight-delays-dev-raw'
os.environ['DLQ_BUCKET'] = 'flight-delays-dev-dlq'
os.environ['AWS_REGION'] = 'us-east-1'

# Import after setting env vars
try:
    from app import log_error_to_dlq
except ImportError:
    print("❌ Error: Could not import app.py")
    print("   Make sure you have dependencies installed:")
    print("   pip3 install boto3 requests")
    sys.exit(1)

def wait_for_user():
    """Wait for user to press Enter"""
    input("\n⏸️  Press Enter to continue to next scenario...")
    print()

print("="*70)
print("DLQ ERROR LOGGING - 3 INTERACTIVE DEMO SCENARIOS")
print("="*70)
print()
print("This script will demonstrate 3 error types with DLQ logging.")
print("After each scenario, you can:")
print("  - Review the error output")
print("  - Check the DLQ S3 bucket")
print("  - Press Enter to continue")
print()
wait_for_user()

# ==============================================================================
# SCENARIO 1: HTTP 404 Error with Full Response
# ==============================================================================
print("\n" + "="*70)
print("📍 SCENARIO 1: HTTP 404 Not Found Error")
print("="*70)
print()
print("What this demonstrates:")
print("  ✓ API endpoint doesn't exist")
print("  ✓ Full HTTP response captured (status, headers, body)")
print("  ✓ Logged to: scraping_errors/YYYY/MM/DD/error_*_api_http_error.json")
print()

try:
    import requests
    bad_url = f"{os.environ['API_ENDPOINT']}/api/v1/wrong_endpoint"
    print(f"🌐 Requesting non-existent endpoint:")
    print(f"   {bad_url}")
    print()
    response = requests.get(bad_url, timeout=10)
    response.raise_for_status()
    print("✅ Request succeeded (unexpected)")
except requests.exceptions.HTTPError as e:
    print(f"❌ HTTP {e.response.status_code} Error Occurred!")
    print(f"   Response length: {len(e.response.text)} characters")
    print(f"   Response preview: {e.response.text[:150]}...")
    print()
    
    log_error_to_dlq(
        error_type='api_http_error',
        error_message=f'API returned HTTP error: {e.response.status_code}',
        context={
            'url': bad_url,
            'status_code': e.response.status_code,
            'data_type': 'weather'
        },
        faulty_response=e.response  # Full HTTP response with headers & body
    )
    print("✅ Error Logged to DLQ Successfully!")
    print()
    print("   What was captured:")
    print(f"   ├─ Status Code: {e.response.status_code}")
    print(f"   ├─ Headers: {len(e.response.headers)} headers")
    print(f"   ├─ Body: {len(e.response.text)} characters (up to 5KB)")
    print(f"   └─ URL: {e.response.url}")
    print()
    print("📁 View in S3:")
    date_path = datetime.now().strftime('%Y/%m/%d')
    print(f"   aws s3 ls s3://flight-delays-dev-dlq/scraping_errors/{date_path}/ | grep api_http_error")
except requests.exceptions.RequestException as e:
    # Catches ALL requests errors: ConnectionError, Timeout, DNSError, etc.
    print(f"❌ Request Error Occurred!")
    print(f"   Error type: {type(e).__name__}")
    print(f"   Error message: {str(e)}")
    print()
    
    log_error_to_dlq(
        error_type='api_request_error',
        error_message=f'API request failed: {str(e)}',
        context={
            'url': bad_url,
            'error_type': type(e).__name__,
            'error': str(e),
            'data_type': 'weather'
        },
        faulty_response=e.response if hasattr(e, 'response') and e.response is not None else None
    )
    print("✅ Error Logged to DLQ Successfully!")
    print()
    print("   What was captured:")
    print(f"   ├─ Error Type: {type(e).__name__}")
    print(f"   ├─ Error Message: {str(e)[:100]}...")
    print(f"   ├─ URL: {bad_url}")
    print(f"   └─ Response: {'Available' if hasattr(e, 'response') and e.response else 'Not available'}")
    print()
    print("📁 View in S3:")
    date_path = datetime.now().strftime('%Y/%m/%d')
    print(f"   aws s3 ls s3://flight-delays-dev-dlq/scraping_errors/{date_path}/ | grep api_request_error")
except Exception as e:
    print(f"⚠️  Unexpected error occurred: {type(e).__name__}: {e}")

wait_for_user()

# ==============================================================================
# SCENARIO 2: JSON Decode Error with Faulty JSON
# ==============================================================================
print("\n" + "="*70)
print("📍 SCENARIO 2: Invalid JSON Response")
print("="*70)
print()
print("What this demonstrates:")
print("  ✓ API returns malformed JSON")
print("  ✓ Raw text captured for debugging")
print("  ✓ Logged to: scraping_errors/YYYY/MM/DD/error_*_json_decode_error.json")
print()

try:
    print("📝 Attempting to parse invalid JSON...")
    invalid_json = '{"weather": "data", "observations": [{"temp": 45.2, "incomplete": '
    print(f"   Faulty JSON: {invalid_json}")
    print()
    parsed = json.loads(invalid_json)
    print("✅ Parse succeeded (unexpected)")
except json.JSONDecodeError as e:
    print(f"❌ JSON Decode Error Occurred!")
    print(f"   Error: {str(e)}")
    print(f"   Position: Character {e.pos}")
    print()
    
    log_error_to_dlq(
        error_type='json_decode_error',
        error_message='Failed to parse API response as JSON',
        context={
            'url': f"{os.environ['API_ENDPOINT']}/api/v1/weather",
            'error': str(e),
            'data_type': 'weather',
            'position': e.pos
        },
        faulty_response=invalid_json  # Raw text that failed to parse
    )
    print("✅ Error Logged to DLQ Successfully!")
    print()
    print("   What was captured:")
    print(f"   ├─ Malformed JSON: {len(invalid_json)} characters")
    print(f"   ├─ Error Position: {e.pos}")
    print(f"   ├─ Error Message: {str(e)}")
    print(f"   └─ Full raw text preserved for debugging")
    print()
    print("📁 View in S3:")
    date_path = datetime.now().strftime('%Y/%m/%d')
    print(f"   aws s3 ls s3://flight-delays-dev-dlq/scraping_errors/{date_path}/ | grep json_decode_error")

wait_for_user()

# ==============================================================================
# SCENARIO 3: S3 Upload Error with Data Sample
# ==============================================================================
print("\n" + "="*70)
print("📍 SCENARIO 3: S3 Upload Error")
print("="*70)
print()
print("What this demonstrates:")
print("  ✓ S3 upload fails (NoSuchBucket)")
print("  ✓ Data sample captured (what we tried to upload)")
print("  ✓ AWS error details captured")
print("  ✓ Logged to: scraping_errors/YYYY/MM/DD/error_*_s3_upload_error.json")
print()

try:
    import boto3
    from botocore.exceptions import ClientError
    
    s3_client = boto3.client('s3', region_name='us-east-1')
    invalid_bucket = "nonexistent-bucket-demo-12345"
    
    test_data = {
        "metadata": {"source": "weather_api", "timestamp": datetime.now().isoformat()},
        "observations": [
            {"station": "KORD", "temp": 45.2, "humidity": 65},
            {"station": "KATL", "temp": 72.1, "humidity": 80},
            {"station": "KDFW", "temp": 68.5, "humidity": 55}
        ]
    }
    
    print(f"☁️  Attempting upload to non-existent bucket:")
    print(f"   Bucket: {invalid_bucket}")
    print(f"   Key: scraped/weather/test.json")
    print(f"   Data: {len(test_data['observations'])} observations")
    print()
    
    s3_client.put_object(
        Bucket=invalid_bucket,
        Key='scraped/weather/test.json',
        Body=json.dumps(test_data, indent=2),
        ContentType='application/json'
    )
    print("✅ Upload succeeded (unexpected)")
    
except ClientError as e:
    error_code = e.response.get('Error', {}).get('Code', 'Unknown')
    error_msg = e.response.get('Error', {}).get('Message', 'Unknown')
    print(f"❌ S3 Upload Error Occurred!")
    print(f"   Error Code: {error_code}")
    print(f"   Message: {error_msg}")
    print()
    
    log_error_to_dlq(
        error_type='s3_upload_error',
        error_message=f'Failed to upload to S3: {error_code}',
        context={
            'bucket': invalid_bucket,
            'key': 'scraped/weather/test.json',
            'record_count': len(test_data['observations']),
            'error_code': error_code
        },
        faulty_response={
            'data_sample': test_data,  # Full data that failed to upload
            'error_response': e.response  # AWS error details
        }
    )
    print("✅ Error Logged to DLQ Successfully!")
    print()
    print("   What was captured:")
    print(f"   ├─ Data Sample: {len(test_data['observations'])} observations")
    print(f"   ├─ Error Code: {error_code}")
    print(f"   ├─ Error Message: {error_msg}")
    print(f"   └─ Full AWS error response preserved")
    print()
    print("📁 View in S3:")
    date_path = datetime.now().strftime('%Y/%m/%d')
    print(f"   aws s3 ls s3://flight-delays-dev-dlq/scraping_errors/{date_path}/ | grep s3_upload_error")

except Exception as e:
    print(f"⚠️  Different error occurred: {e}")

# ==============================================================================
# Summary
# ==============================================================================
print()
print("="*70)
print("✅ ALL 3 SCENARIOS COMPLETED")
print("="*70)
print()
print("🎯 Summary of Errors Logged:")
print("   1. HTTP 404 Error → Full HTTP response captured")
print("   2. JSON Decode Error → Raw malformed JSON text captured")
print("   3. S3 Upload Error → Data sample + AWS error details captured")
print()
print("📁 View all errors in DLQ:")
date_path = datetime.now().strftime('%Y/%m/%d')
print(f"   aws s3 ls s3://flight-delays-dev-dlq/scraping_errors/{date_path}/ --recursive")
print()
print("📊 Download and view a specific error:")
print(f"   aws s3 cp s3://flight-delays-dev-dlq/scraping_errors/{date_path}/error_*_api_http_error.json - | jq .")
print()
print("🔍 Key Features Demonstrated:")
print("   ✓ Comprehensive error context")
print("   ✓ Faulty responses captured for debugging")
print("   ✓ Organized by date (YYYY/MM/DD)")
print("   ✓ Error type in filename for easy filtering")
print()
