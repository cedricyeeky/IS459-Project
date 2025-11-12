#!/usr/bin/env python3
"""
Mock API Data Scraper
Fetches weather and realtime flight data from mock API and uploads to S3
"""

import os
import sys
import json
import logging
from datetime import datetime, timezone
from typing import Dict, Any, Optional
import requests
import boto3
from botocore.exceptions import ClientError

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[logging.StreamHandler(sys.stdout)]
)
logger = logging.getLogger(__name__)

# Environment variables
API_ENDPOINT = os.environ.get('API_ENDPOINT', 'http://localhost:5200')
S3_BUCKET = os.environ.get('S3_BUCKET')
DLQ_BUCKET = os.environ.get('DLQ_BUCKET', S3_BUCKET)  # Use same bucket if not specified
AWS_REGION = os.environ.get('AWS_REGION', 'us-east-1')
REQUEST_TIMEOUT = int(os.environ.get('REQUEST_TIMEOUT', '30'))

# Initialize S3 client
s3_client = boto3.client('s3', region_name=AWS_REGION)


class ScraperError(Exception):
    """Base exception for scraper errors"""
    pass


class APIError(ScraperError):
    """Exception raised for API-related errors"""
    pass


class S3UploadError(ScraperError):
    """Exception raised for S3 upload errors"""
    pass


def log_error_to_dlq(error_type: str, error_message: str, context: Dict[str, Any], faulty_response: Any = None) -> bool:
    """
    Log error to DLQ S3 bucket for monitoring and debugging
    Logs to: s3://dlq/scraping_errors/YYYY/MM/DD/error_TIMESTAMP.json
    
    Args:
        error_type: Type of error (e.g., 'api_timeout', 's3_upload_error')
        error_message: Detailed error message
        context: Additional context information
        faulty_response: The faulty response/data that caused the error (optional)
        
    Returns:
        True if logged successfully, False otherwise
    """
    try:
        timestamp = datetime.now(timezone.utc)
        
        # Create error record
        error_record = {
            'error_type': error_type,
            'error_message': error_message,
            'timestamp': timestamp.isoformat(),
            'context': context,
            'scraper_info': {
                'api_endpoint': API_ENDPOINT,
                's3_bucket': S3_BUCKET,
                'dlq_bucket': DLQ_BUCKET,
                'aws_region': AWS_REGION
            }
        }
        
        # Include faulty response if provided
        if faulty_response is not None:
            # Convert response to JSON-serializable format
            try:
                if isinstance(faulty_response, requests.Response):
                    error_record['faulty_response'] = {
                        'status_code': faulty_response.status_code,
                        'headers': dict(faulty_response.headers),
                        'body': faulty_response.text[:5000],  # Limit to 5KB
                        'url': faulty_response.url
                    }
                elif isinstance(faulty_response, dict):
                    # Already JSON-serializable
                    error_record['faulty_response'] = faulty_response
                else:
                    # Convert to string
                    error_record['faulty_response'] = str(faulty_response)[:5000]
            except Exception as e:
                error_record['faulty_response_error'] = f"Failed to serialize response: {str(e)}"
        
        # S3 key with date-based partitioning: scraping_errors/YYYY/MM/DD/error_TIMESTAMP.json
        s3_key = (
            f"scraping_errors/"
            f"{timestamp.strftime('%Y/%m/%d')}/"
            f"error_{timestamp.strftime('%Y%m%d_%H%M%S')}_{error_type}.json"
        )
        
        # Upload error to DLQ
        s3_client.put_object(
            Bucket=DLQ_BUCKET,
            Key=s3_key,
            Body=json.dumps(error_record, indent=2),
            ContentType='application/json',
            Metadata={
                'error_type': error_type,
                'timestamp': timestamp.isoformat(),
                'source': 'scraper'
            }
        )
        
        logger.info(f"Logged error to DLQ: s3://{DLQ_BUCKET}/{s3_key}")
        return True
        
    except Exception as e:
        # If DLQ logging fails, log to CloudWatch but don't crash
        logger.error(f"Failed to log error to DLQ: {e}")
        return False


def fetch_weather_data() -> Optional[Dict[str, Any]]:
    """
    Fetch weather data from mock API
    
    Returns:
        Dictionary containing weather observations or None if failed
        
    Raises:
        APIError: If API request fails
    """
    url = f"{API_ENDPOINT}/api/v1/weather"
    
    try:
        logger.info(f"Fetching weather data from {url}")
        response = requests.get(url, timeout=REQUEST_TIMEOUT)
        response.raise_for_status()
        
        data = response.json()
        
        # Validate response structure
        if 'observations' not in data:
            raise APIError("Invalid weather response: missing 'observations' key")
        
        observation_count = len(data.get('observations', []))
        logger.info(f"Successfully fetched {observation_count} weather observations")
        
        if observation_count == 0:
            logger.warning("Weather API returned 0 observations")
        
        return data
        
    except requests.exceptions.Timeout as e:
        error_msg = f"Weather API request timed out after {REQUEST_TIMEOUT}s"
        logger.error(error_msg)
        log_error_to_dlq(
            error_type='api_timeout',
            error_message=error_msg,
            context={'url': url, 'timeout': REQUEST_TIMEOUT, 'data_type': 'weather'}
        )
        raise APIError(error_msg) from e
        
    except requests.exceptions.HTTPError as e:
        error_msg = f"Weather API returned HTTP error: {e.response.status_code}"
        logger.error(error_msg)
        log_error_to_dlq(
            error_type='api_http_error',
            error_message=error_msg,
            context={
                'url': url,
                'status_code': e.response.status_code,
                'data_type': 'weather'
            },
            faulty_response=e.response
        )
        raise APIError(error_msg) from e
        
    except requests.exceptions.RequestException as e:
        error_msg = f"Weather API request failed: {str(e)}"
        logger.error(error_msg)
        log_error_to_dlq(
            error_type='api_request_error',
            error_message=error_msg,
            context={'url': url, 'error': str(e), 'data_type': 'weather'},
            faulty_response=e.response if hasattr(e, 'response') and e.response is not None else None
        )
        raise APIError(error_msg) from e
        
    except json.JSONDecodeError as e:
        error_msg = f"Failed to parse weather API response as JSON"
        logger.error(error_msg)
        log_error_to_dlq(
            error_type='json_decode_error',
            error_message=error_msg,
            context={'url': url, 'error': str(e), 'data_type': 'weather'},
            faulty_response=response.text if 'response' in locals() else None
        )
        raise APIError(error_msg) from e


def fetch_realtime_flights() -> Optional[Dict[str, Any]]:
    """
    Fetch realtime flight data from mock API
    
    Returns:
        Dictionary containing flight data or None if failed
        
    Raises:
        APIError: If API request fails
    """
    url = f"{API_ENDPOINT}/api/v1/flights/realtime"
    
    try:
        logger.info(f"Fetching realtime flight data from {url}")
        response = requests.get(url, timeout=REQUEST_TIMEOUT)
        response.raise_for_status()
        
        data = response.json()
        
        # Validate response structure
        if 'flights' not in data:
            raise APIError("Invalid flights response: missing 'flights' key")
        
        flight_count = len(data.get('flights', []))
        logger.info(f"Successfully fetched {flight_count} flight records")
        
        if flight_count == 0:
            logger.warning("Flights API returned 0 records")
        
        return data
        
    except requests.exceptions.Timeout as e:
        error_msg = f"Flights API request timed out after {REQUEST_TIMEOUT}s"
        logger.error(error_msg)
        log_error_to_dlq(
            error_type='api_timeout',
            error_message=error_msg,
            context={'url': url, 'timeout': REQUEST_TIMEOUT, 'data_type': 'flights'}
        )
        raise APIError(error_msg) from e
        
    except requests.exceptions.HTTPError as e:
        error_msg = f"Flights API returned HTTP error: {e.response.status_code}"
        logger.error(error_msg)
        log_error_to_dlq(
            error_type='api_http_error',
            error_message=error_msg,
            context={
                'url': url,
                'status_code': e.response.status_code,
                'data_type': 'flights'
            },
            faulty_response=e.response
        )
        raise APIError(error_msg) from e
        
    except requests.exceptions.RequestException as e:
        error_msg = f"Flights API request failed: {str(e)}"
        logger.error(error_msg)
        log_error_to_dlq(
            error_type='api_request_error',
            error_message=error_msg,
            context={'url': url, 'error': str(e), 'data_type': 'flights'},
            faulty_response=e.response if hasattr(e, 'response') and e.response is not None else None
        )
        raise APIError(error_msg) from e
        
    except json.JSONDecodeError as e:
        error_msg = f"Failed to parse flights API response as JSON"
        logger.error(error_msg)
        log_error_to_dlq(
            error_type='json_decode_error',
            error_message=error_msg,
            context={'url': url, 'error': str(e), 'data_type': 'flights'},
            faulty_response=response.text if 'response' in locals() else None
        )
        raise APIError(error_msg) from e


def upload_to_s3(data: Dict[str, Any], data_type: str, timestamp: datetime) -> bool:
    """
    Upload data to S3 with flat path structure
    
    Args:
        data: The data to upload (weather or flights)
        data_type: Type of data ('weather' or 'flights')
        timestamp: Timestamp for file organization
        
    Returns:
        True if successful, False otherwise
        
    Raises:
        S3UploadError: If S3 upload fails
    """
    if not S3_BUCKET:
        error_msg = "S3_BUCKET environment variable not set"
        logger.error(error_msg)
        log_error_to_dlq(
            error_type='configuration_error',
            error_message=error_msg,
            context={'data_type': data_type}
        )
        raise S3UploadError(error_msg)
    
    try:
        # Generate filename with timestamp
        filename = f"{data_type}_{timestamp.strftime('%Y%m%d_%H%M%S')}.json"
        
        # S3 key with flat structure: scraped/{data_type}/filename.json
        s3_key = f"scraped/{data_type}/{filename}"
        
        # Extract record count for logging
        record_count = len(data.get('observations' if data_type == 'weather' else 'flights', []))
        
        # Convert data to JSON string
        json_data = json.dumps(data, indent=2)
        
        # Upload to S3
        logger.info(f"Uploading {data_type} data to s3://{S3_BUCKET}/{s3_key} ({record_count} records)")
        s3_client.put_object(
            Bucket=S3_BUCKET,
            Key=s3_key,
            Body=json_data,
            ContentType='application/json',
            Metadata={
                'data_type': data_type,
                'scraped_at': timestamp.isoformat(),
                'record_count': str(record_count)
            }
        )
        
        logger.info(f"Successfully uploaded {data_type} data to S3: {s3_key}")
        return True
        
    except ClientError as e:
        error_code = e.response.get('Error', {}).get('Code', 'Unknown')
        error_msg = f"Failed to upload {data_type} to S3: {error_code} - {str(e)}"
        logger.error(error_msg)
        
        log_error_to_dlq(
            error_type='s3_upload_error',
            error_message=error_msg,
            context={
                'bucket': S3_BUCKET,
                'key': s3_key,
                'data_type': data_type,
                'record_count': record_count,
                'error_code': error_code,
                'error_details': str(e)
            },
            faulty_response={
                'data_sample': data if len(json.dumps(data)) < 10000 else str(data)[:10000],
                'error_response': e.response
            }
        )
        raise S3UploadError(error_msg) from e
        
    except Exception as e:
        error_msg = f"Unexpected error uploading {data_type} to S3: {str(e)}"
        logger.error(error_msg)
        
        log_error_to_dlq(
            error_type='s3_upload_unexpected_error',
            error_message=error_msg,
            context={
                'bucket': S3_BUCKET,
                'key': s3_key if 's3_key' in locals() else 'unknown',
                'data_type': data_type,
                'error': str(e),
                'error_type': type(e).__name__
            }
        )
        raise S3UploadError(error_msg) from e


def verify_api_health() -> bool:
    """
    Verify the mock API is healthy before scraping
    
    Returns:
        True if API is healthy, False otherwise
    """
    url = f"{API_ENDPOINT}/health"
    
    try:
        logger.info(f"Checking API health at {url}")
        response = requests.get(url, timeout=10)
        response.raise_for_status()
        
        health_data = response.json()
        status = health_data.get('status')
        
        if status == 'healthy':
            logger.info(f"API is healthy (version: {health_data.get('version', 'unknown')})")
            return True
        else:
            logger.warning(f"API returned unhealthy status: {status}")
            return False
            
    except requests.exceptions.RequestException as e:
        logger.error(f"API health check failed: {e}")
        return False


def run_scraper() -> int:
    """
    Main scraper execution function
    
    Returns:
        Exit code (0 for success, 1 for failure)
    """
    logger.info("="*70)
    logger.info("Starting Mock API Data Scraper")
    logger.info("="*70)
    logger.info(f"API Endpoint: {API_ENDPOINT}")
    logger.info(f"S3 Bucket: {S3_BUCKET}")
    logger.info(f"DLQ Bucket: {DLQ_BUCKET}")
    logger.info(f"AWS Region: {AWS_REGION}")
    
    # Verify configuration
    if not S3_BUCKET:
        error_msg = "S3_BUCKET environment variable is required"
        logger.error(error_msg)
        log_error_to_dlq(
            error_type='configuration_error',
            error_message=error_msg,
            context={'phase': 'initialization'}
        )
        return 1
    
    try:
        # Get current timestamp
        scrape_timestamp = datetime.now(timezone.utc)
        logger.info(f"Scrape timestamp: {scrape_timestamp.isoformat()}")
        
        # Verify API health
        if not verify_api_health():
            error_msg = "API health check failed, aborting scrape"
            logger.error(error_msg)
            log_error_to_dlq(
                error_type='api_health_check_failed',
                error_message=error_msg,
                context={'phase': 'pre_flight_check', 'api_endpoint': API_ENDPOINT}
            )
            return 1
        
        # Track success/failure
        success_count = 0
        failure_count = 0
        errors = []
        
        # Fetch and upload weather data
        logger.info("-"*70)
        logger.info("Fetching weather data...")
        try:
            weather_data = fetch_weather_data()
            upload_to_s3(weather_data, 'weather', scrape_timestamp)
            success_count += 1
            logger.info("Weather data processed successfully")
        except (APIError, S3UploadError) as e:
            failure_count += 1
            errors.append(f"Weather: {str(e)}")
            logger.error(f"Weather processing failed: {e}")
        except Exception as e:
            failure_count += 1
            errors.append(f"Weather (unexpected): {str(e)}")
            logger.exception(f"Unexpected error processing weather data: {e}")
            log_error_to_dlq(
                error_type='unexpected_weather_error',
                error_message=str(e),
                context={'phase': 'weather_processing', 'error_type': type(e).__name__}
            )
        
        # Fetch and upload realtime flights
        logger.info("-"*70)
        logger.info("Fetching realtime flights...")
        try:
            flights_data = fetch_realtime_flights()
            upload_to_s3(flights_data, 'flights', scrape_timestamp)
            success_count += 1
            logger.info("Flights data processed successfully")
        except (APIError, S3UploadError) as e:
            failure_count += 1
            errors.append(f"Flights: {str(e)}")
            logger.error(f"Flights processing failed: {e}")
        except Exception as e:
            failure_count += 1
            errors.append(f"Flights (unexpected): {str(e)}")
            logger.exception(f"Unexpected error processing flights data: {e}")
            log_error_to_dlq(
                error_type='unexpected_flights_error',
                error_message=str(e),
                context={'phase': 'flights_processing', 'error_type': type(e).__name__}
            )
        
        # Summary
        logger.info("="*70)
        logger.info(f"Scraper execution completed")
        logger.info(f"Successful uploads: {success_count}/2")
        logger.info(f"Failed uploads: {failure_count}/2")
        
        if errors:
            logger.warning(f"Errors encountered:")
            for error in errors:
                logger.warning(f"  - {error}")
        
        logger.info("="*70)
        
        # Return exit code based on results
        if failure_count > 0:
            logger.warning(f"Scraper completed with {failure_count} failure(s)")
            return 1
        else:
            logger.info("Scraper completed successfully")
            return 0
            
    except Exception as e:
        # Catch-all for unexpected errors during scraper execution
        error_msg = f"Scraper execution failed with unexpected error: {str(e)}"
        logger.exception(error_msg)
        log_error_to_dlq(
            error_type='scraper_execution_error',
            error_message=error_msg,
            context={
                'phase': 'execution',
                'error_type': type(e).__name__,
                'error_details': str(e)
            }
        )
        return 1


if __name__ == "__main__":
    try:
        exit_code = run_scraper()
        sys.exit(exit_code)
    except Exception as e:
        logger.exception(f"Fatal error in scraper: {e}")
        log_error_to_dlq(
            error_type='fatal_error',
            error_message=str(e),
            context={
                'phase': 'main',
                'error_type': type(e).__name__
            }
        )
        sys.exit(1)
