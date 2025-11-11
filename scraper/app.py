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
AWS_REGION = os.environ.get('AWS_REGION', 'us-east-1')
REQUEST_TIMEOUT = int(os.environ.get('REQUEST_TIMEOUT', '30'))

# Initialize S3 client
s3_client = boto3.client('s3', region_name=AWS_REGION)


class ScraperError(Exception):
    """Base exception for scraper errors"""
    pass


def fetch_weather_data() -> Optional[Dict[str, Any]]:
    """
    Fetch weather data from mock API
    
    Returns:
        Dictionary containing weather observations or None if failed
    """
    url = f"{API_ENDPOINT}/api/v1/weather"
    
    try:
        logger.info(f"Fetching weather data from {url}")
        response = requests.get(url, timeout=REQUEST_TIMEOUT)
        response.raise_for_status()
        
        data = response.json()
        logger.info(f"Successfully fetched {len(data.get('observations', []))} weather observations")
        return data
        
    except requests.exceptions.RequestException as e:
        logger.error(f"Failed to fetch weather data: {e}")
        return None


def fetch_realtime_flights() -> Optional[Dict[str, Any]]:
    """
    Fetch realtime flight data from mock API
    
    Returns:
        Dictionary containing flight data or None if failed
    """
    url = f"{API_ENDPOINT}/api/v1/flights/realtime"
    
    try:
        logger.info(f"Fetching realtime flights from {url}")
        response = requests.get(url, timeout=REQUEST_TIMEOUT)
        response.raise_for_status()
        
        data = response.json()
        logger.info(f"Successfully fetched {len(data.get('flights', []))} realtime flights")
        return data
        
    except requests.exceptions.RequestException as e:
        logger.error(f"Failed to fetch realtime flights: {e}")
        return None


def upload_to_s3(data: Dict[str, Any], data_type: str, timestamp: datetime) -> bool:
    """
    Upload data to S3 with flat path structure
    
    Args:
        data: The data to upload (weather or flights)
        data_type: Type of data ('weather' or 'flights')
        timestamp: Timestamp for file organization
        
    Returns:
        True if successful, False otherwise
    """
    if not S3_BUCKET:
        logger.error("S3_BUCKET environment variable not set")
        return False
    
    try:
        # Generate filename with timestamp
        filename = f"{data_type}_{timestamp.strftime('%Y%m%d_%H%M%S')}.json"
        
        # S3 key with flat structure: scraped/{data_type}/filename.json
        s3_key = f"scraped/{data_type}/{filename}"
        
        # Convert data to JSON string
        json_data = json.dumps(data, indent=2)
        
        # Upload to S3
        logger.info(f"Uploading {data_type} data to s3://{S3_BUCKET}/{s3_key}")
        s3_client.put_object(
            Bucket=S3_BUCKET,
            Key=s3_key,
            Body=json_data,
            ContentType='application/json',
            Metadata={
                'data_type': data_type,
                'scraped_at': timestamp.isoformat(),
                'record_count': str(len(data.get('observations' if data_type == 'weather' else 'flights', [])))
            }
        )
        
        logger.info(f"Successfully uploaded {data_type} data to S3: {s3_key}")
        return True
        
    except ClientError as e:
        logger.error(f"Failed to upload {data_type} data to S3: {e}")
        return False
    except Exception as e:
        logger.error(f"Unexpected error uploading {data_type} data: {e}")
        return False


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
    logger.info(f"AWS Region: {AWS_REGION}")
    
    # Verify configuration
    if not S3_BUCKET:
        logger.error("S3_BUCKET environment variable is required")
        return 1
    
    # Get current timestamp
    scrape_timestamp = datetime.now(timezone.utc)
    logger.info(f"Scrape timestamp: {scrape_timestamp.isoformat()}")
    
    # Verify API health
    if not verify_api_health():
        logger.error("API health check failed, aborting scrape")
        return 1
    
    # Track success/failure
    success_count = 0
    failure_count = 0
    
    # Fetch and upload weather data
    logger.info("-"*70)
    logger.info("Fetching weather data...")
    weather_data = fetch_weather_data()
    if weather_data:
        if upload_to_s3(weather_data, 'weather', scrape_timestamp):
            success_count += 1
        else:
            failure_count += 1
    else:
        failure_count += 1
    
    # Fetch and upload realtime flights
    logger.info("-"*70)
    logger.info("Fetching realtime flights...")
    flights_data = fetch_realtime_flights()
    if flights_data:
        if upload_to_s3(flights_data, 'flights', scrape_timestamp):
            success_count += 1
        else:
            failure_count += 1
    else:
        failure_count += 1
    
    # Summary
    logger.info("="*70)
    logger.info(f"Scraper execution completed")
    logger.info(f"Successful uploads: {success_count}/2")
    logger.info(f"Failed uploads: {failure_count}/2")
    logger.info("="*70)
    
    # Return exit code based on results
    if failure_count > 0:
        logger.warning(f"Scraper completed with {failure_count} failure(s)")
        return 1
    else:
        logger.info("Scraper completed successfully")
        return 0


if __name__ == "__main__":
    try:
        exit_code = run_scraper()
        sys.exit(exit_code)
    except Exception as e:
        logger.exception(f"Unexpected error in scraper: {e}")
        sys.exit(1)
