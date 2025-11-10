#!/usr/bin/env python3
"""
Test script for Mock Flight Data API
Run this after starting the API to verify functionality
"""

import requests
import json
from datetime import datetime

API_BASE_URL = "http://localhost:5000"


def test_health():
    """Test health endpoint"""
    print("Testing /health endpoint...")
    response = requests.get(f"{API_BASE_URL}/health")
    assert response.status_code == 200
    data = response.json()
    assert data['status'] == 'healthy'
    print("✓ Health check passed")
    print(f"  Status: {data['status']}")
    print(f"  Timestamp: {data['timestamp']}\n")


def test_root():
    """Test root documentation endpoint"""
    print("Testing / endpoint...")
    response = requests.get(f"{API_BASE_URL}/")
    assert response.status_code == 200
    data = response.json()
    assert 'service' in data
    assert 'endpoints' in data
    print("✓ Root endpoint passed")
    print(f"  Service: {data['service']}")
    print(f"  Version: {data['version']}\n")


def test_flights_basic():
    """Test basic flights endpoint"""
    print("Testing /api/v1/flights endpoint (basic)...")
    response = requests.get(f"{API_BASE_URL}/api/v1/flights", params={'limit': 10})
    assert response.status_code == 200
    data = response.json()
    
    assert 'metadata' in data
    assert 'summary_statistics' in data
    assert 'flights' in data
    assert len(data['flights']) == 10
    
    print("✓ Basic flights endpoint passed")
    print(f"  Total records: {data['metadata']['total_records']}")
    print(f"  On-time rate: {data['summary_statistics']['on_time_rate']}%")
    print(f"  Delay rate: {data['summary_statistics']['delay_rate']}%")
    print(f"  Cancellation rate: {data['summary_statistics']['cancellation_rate']}%\n")


def test_flights_with_filters():
    """Test flights endpoint with filters"""
    print("Testing /api/v1/flights endpoint (with filters)...")
    
    # Test carrier filter
    response = requests.get(f"{API_BASE_URL}/api/v1/flights", params={
        'limit': 20,
        'carrier': 'AA'
    })
    assert response.status_code == 200
    data = response.json()
    
    # Verify all flights are from AA
    for flight in data['flights']:
        assert flight['carrier_code'] == 'AA'
    
    print("✓ Carrier filter passed")
    print(f"  Filtered to carrier: AA")
    print(f"  Total records: {len(data['flights'])}\n")
    
    # Test status filter
    response = requests.get(f"{API_BASE_URL}/api/v1/flights", params={
        'limit': 50,
        'status': 'DELAYED'
    })
    assert response.status_code == 200
    data = response.json()
    
    # Verify all flights are delayed
    for flight in data['flights']:
        assert flight['status'] == 'DELAYED'
    
    print("✓ Status filter passed")
    print(f"  Filtered to status: DELAYED")
    print(f"  Total records: {len(data['flights'])}\n")


def test_realtime_flights():
    """Test real-time flights endpoint"""
    print("Testing /api/v1/flights/realtime endpoint...")
    response = requests.get(f"{API_BASE_URL}/api/v1/flights/realtime", params={'limit': 20})
    assert response.status_code == 200
    data = response.json()
    
    assert 'metadata' in data
    assert 'flights' in data
    assert 'window_hours' in data['metadata']
    
    print("✓ Real-time flights endpoint passed")
    print(f"  Total records: {data['metadata']['total_records']}")
    print(f"  Time window: {data['metadata']['window_hours']} hours\n")


def test_stats():
    """Test stats endpoint"""
    print("Testing /api/v1/stats endpoint...")
    response = requests.get(f"{API_BASE_URL}/api/v1/stats")
    assert response.status_code == 200
    data = response.json()
    
    assert 'api_info' in data
    assert 'data_metrics' in data
    assert 'carrier_reliability' in data
    
    print("✓ Stats endpoint passed")
    print(f"  Carriers available: {data['data_metrics']['carriers_available']}")
    print(f"  Airports available: {data['data_metrics']['airports_available']}")
    print(f"  Default rows: {data['data_metrics']['default_rows_per_request']}\n")
    
    print("Top 3 carriers by reliability:")
    for carrier in data['carrier_reliability'][:3]:
        print(f"  {carrier['code']} ({carrier['name']}): {carrier['reliability_score']}")
    print()


def test_data_quality():
    """Test data quality and schema"""
    print("Testing data quality and schema...")
    response = requests.get(f"{API_BASE_URL}/api/v1/flights", params={'limit': 5})
    data = response.json()
    
    flight = data['flights'][0]
    
    # Verify required fields exist
    required_fields = [
        'flight_id', 'flight_number', 'carrier_code', 'carrier_name',
        'origin_airport', 'destination_airport', 'scheduled_departure',
        'scheduled_arrival', 'status', 'on_time', 'reliability_band',
        'flight_date', 'timestamp'
    ]
    
    for field in required_fields:
        assert field in flight, f"Missing required field: {field}"
    
    print("✓ Data quality check passed")
    print(f"  All required fields present")
    print(f"\n  Sample flight record:")
    print(f"  Flight: {flight['flight_number']}")
    print(f"  Carrier: {flight['carrier_name']} ({flight['carrier_code']})")
    print(f"  Route: {flight['origin_airport']} → {flight['destination_airport']}")
    print(f"  Status: {flight['status']}")
    print(f"  Reliability: {flight['reliability_band']}")
    print(f"  On-time: {flight['on_time']}\n")


def test_error_handling():
    """Test error handling"""
    print("Testing error handling...")
    
    # Test invalid date format
    response = requests.get(f"{API_BASE_URL}/api/v1/flights", params={
        'date': 'invalid-date'
    })
    assert response.status_code == 400
    
    # Test invalid endpoint
    response = requests.get(f"{API_BASE_URL}/api/v1/invalid")
    assert response.status_code == 404
    
    print("✓ Error handling passed")
    print(f"  Invalid date: 400 Bad Request")
    print(f"  Invalid endpoint: 404 Not Found\n")


def print_sample_json():
    """Print a sample JSON response for documentation"""
    print("="*80)
    print("Sample JSON Response:")
    print("="*80)
    
    response = requests.get(f"{API_BASE_URL}/api/v1/flights", params={'limit': 1})
    data = response.json()
    
    sample = {
        'metadata': data['metadata'],
        'summary_statistics': data['summary_statistics'],
        'flights': [data['flights'][0]] if data['flights'] else []
    }
    
    print(json.dumps(sample, indent=2))
    print()


def run_all_tests():
    """Run all tests"""
    print("="*80)
    print("Mock Flight Data API - Test Suite")
    print("="*80)
    print(f"Testing API at: {API_BASE_URL}")
    print(f"Started at: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print("="*80)
    print()
    
    try:
        test_health()
        test_root()
        test_flights_basic()
        test_flights_with_filters()
        test_realtime_flights()
        test_stats()
        test_data_quality()
        test_error_handling()
        print_sample_json()
        
        print("="*80)
        print("✓ ALL TESTS PASSED")
        print("="*80)
        print(f"\nThe mock API is ready for your ECS scraper to use!")
        print(f"Your scraper can poll: {API_BASE_URL}/api/v1/flights/realtime")
        print(f"Every 15 minutes via EventBridge scheduler\n")
        
    except AssertionError as e:
        print(f"\n✗ TEST FAILED: {e}")
        return 1
    except requests.exceptions.ConnectionError:
        print(f"\n✗ CONNECTION ERROR: Could not connect to {API_BASE_URL}")
        print("Make sure the API is running:")
        print("  - Docker: docker-compose up -d")
        print("  - Local: python app.py")
        return 1
    except Exception as e:
        print(f"\n✗ UNEXPECTED ERROR: {e}")
        return 1
    
    return 0


if __name__ == '__main__':
    exit(run_all_tests())
