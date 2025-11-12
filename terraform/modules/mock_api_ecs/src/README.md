# Mock Flight Data API

A realistic mock API that generates flight data for testing your ECS scraper. Designed to support the business question: **"By optimizing Flight Reliability, we aim to improve travel satisfaction for travelers and improve the reputation of booking platforms via data transparency."**

## 🎯 Business Focus

This API provides data aligned with your flight reliability analysis:
- **On-time performance** metrics
- **Delay patterns** and root causes
- **Carrier reliability** scores
- **Cascade risk** indicators
- **Traveler-facing reliability** bands (Excellent/Good/Fair/Poor)

## 📊 API Endpoints

### 1. Get Flight Data
```bash
GET /api/v1/flights
```

**Parameters:**
- `limit` (optional): Number of records (default: 100, max: 1000)
- `date` (optional): Filter by date (YYYY-MM-DD format)
- `carrier` (optional): Filter by carrier code (AA, DL, UA, etc.)
- `origin` (optional): Filter by origin airport (ATL, LAX, etc.)
- `destination` (optional): Filter by destination airport
- `status` (optional): Filter by status (SCHEDULED, DEPARTED, ARRIVED, DELAYED, CANCELLED)

**Example:**
```bash
curl "http://localhost:5000/api/v1/flights?limit=50&carrier=AA&status=DELAYED"
```

**Response:**
```json
{
  "metadata": {
    "total_records": 50,
    "timestamp": "2024-11-04T15:30:00Z",
    "api_version": "v1"
  },
  "summary_statistics": {
    "on_time_rate": 78.5,
    "delay_rate": 18.2,
    "cancellation_rate": 3.3,
    "average_delay_minutes": 42.5
  },
  "flights": [...]
}
```

### 2. Get Real-Time Updates
```bash
GET /api/v1/flights/realtime
```

Returns flights within a 2-hour window of current time.

**Example:**
```bash
curl "http://localhost:5000/api/v1/flights/realtime?limit=30"
```

### 3. Get API Statistics
```bash
GET /api/v1/stats
```

Returns API metadata, carrier reliability scores, and configuration.

**Example:**
```bash
curl "http://localhost:5000/api/v1/stats"
```

### 4. Health Check
```bash
GET /health
```

Health check endpoint for monitoring and load balancers.

## 📦 Data Schema

Each flight record includes:

```json
{
  "flight_id": "AA1234_20241104_ATL_LAX",
  "flight_number": "AA1234",
  "tail_number": "N123AA",
  "aircraft_type": "Boeing 737",
  
  "carrier_code": "AA",
  "carrier_name": "American Airlines",
  "carrier_reliability_score": 0.82,
  
  "origin_airport": "ATL",
  "origin_city": "Atlanta",
  "destination_airport": "LAX",
  "destination_city": "Los Angeles",
  
  "scheduled_departure": "2024-11-04T08:30:00",
  "scheduled_arrival": "2024-11-04T11:45:00",
  "actual_departure": "2024-11-04T08:47:00",
  "actual_arrival": "2024-11-04T12:02:00",
  
  "departure_delay_minutes": 17,
  "arrival_delay_minutes": 17,
  "delay_reason": "CARRIER",
  "is_delayed": true,
  "is_cancelled": false,
  
  "status": "ARRIVED",
  
  "on_time": false,
  "cascade_risk": false,
  "reliability_band": "GOOD",
  
  "flight_date": "2024-11-04",
  "day_of_week": "Monday",
  "hour_of_day": 8,
  "timestamp": "2024-11-04T15:30:00Z"
}
```

## 🚀 Quick Start

### Option 1: Run with Docker (Recommended)

```bash
# Build and start the container
docker-compose up -d

# Check logs
docker-compose logs -f

# Stop the container
docker-compose down
```

The API will be available at `http://localhost:5000`

### Option 2: Run with Docker (Manual)

```bash
# Build the image
docker build -t flight-mock-api .

# Run the container
docker run -d \
  -p 5000:5000 \
  -e ROWS_PER_REQUEST=100 \
  --name flight-mock-api \
  flight-mock-api

# Check logs
docker logs -f flight-mock-api

# Stop and remove
docker stop flight-mock-api
docker rm flight-mock-api
```

### Option 3: Run Locally (Development)

```bash
# Create virtual environment
python3 -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Copy environment file
cp .env.example .env

# Run the app
python app.py
```

The API will be available at `http://localhost:5000`

## 🧪 Testing the API

### Basic Test
```bash
# Test health check
curl http://localhost:5000/health

# Get API documentation
curl http://localhost:5000/

# Get 10 flight records
curl "http://localhost:5000/api/v1/flights?limit=10"
```

### Advanced Tests
```bash
# Get delayed flights for a specific date
curl "http://localhost:5000/api/v1/flights?date=2024-11-04&status=DELAYED&limit=20"

# Get Delta Airlines flights from Atlanta
curl "http://localhost:5000/api/v1/flights?carrier=DL&origin=ATL&limit=50"

# Get real-time updates
curl "http://localhost:5000/api/v1/flights/realtime?limit=30"

# Get carrier statistics
curl "http://localhost:5000/api/v1/stats"
```

### Test with Python
```python
import requests
import json

# Get flight data
response = requests.get(
    'http://localhost:5000/api/v1/flights',
    params={'limit': 50, 'carrier': 'AA'}
)

data = response.json()
print(f"Total flights: {data['metadata']['total_records']}")
print(f"On-time rate: {data['summary_statistics']['on_time_rate']}%")

# Pretty print first flight
print(json.dumps(data['flights'][0], indent=2))
```

## 🔄 Integration with ECS Scraper

Your ECS scraper should be configured to:

1. **Poll every 15 minutes** (triggered by EventBridge)
2. **Fetch data** from `/api/v1/flights` or `/api/v1/flights/realtime`
3. **Store raw data** in S3 Raw bucket (`s3://flight-delays-dev-raw/scraped/`)
4. **Handle pagination** if you need more than 1000 records per call

### Example ECS Scraper Code

```python
import requests
from datetime import datetime
import boto3
import json

def scrape_flight_data():
    # Call the mock API
    response = requests.get(
        'http://your-mock-api-url:5000/api/v1/flights/realtime',
        params={'limit': 100}
    )
    
    if response.status_code == 200:
        data = response.json()
        
        # Upload to S3
        s3 = boto3.client('s3')
        timestamp = datetime.utcnow().strftime('%Y%m%d_%H%M%S')
        
        s3.put_object(
            Bucket='flight-delays-dev-raw',
            Key=f'scraped/flights/{timestamp}.json',
            Body=json.dumps(data)
        )
        
        print(f"Scraped {data['metadata']['total_records']} flights")
    else:
        print(f"Error: {response.status_code}")

if __name__ == '__main__':
    scrape_flight_data()
```

## 📈 Data Characteristics

The mock API generates realistic data with:

- **8 major carriers** with varying reliability scores (72-88%)
- **15 major airports** across the US
- **Realistic delay patterns**:
  - Peak hours (6-9 AM, 4-8 PM) have 50% higher delays
  - Red-eye flights (midnight-5 AM) have 30% lower delays
- **Delay reasons** with realistic distributions:
  - Carrier: 30%
  - Weather: 25%
  - Late Aircraft: 20%
  - NAS: 20%
  - Security: 5%
- **Cancellation rates**: 0-3% based on carrier reliability
- **Flight statuses**: SCHEDULED, DEPARTED, ARRIVED, DELAYED, CANCELLED
- **Reliability bands**: EXCELLENT, GOOD, FAIR, POOR

## 🔧 Configuration

Environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `PORT` | 5000 | API port |
| `DEBUG` | False | Flask debug mode |
| `ROWS_PER_REQUEST` | 100 | Default records per request |

## 🐳 Deploying to AWS ECS

### 1. Push Image to ECR

```bash
# Authenticate Docker to ECR
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin <account-id>.dkr.ecr.us-east-1.amazonaws.com

# Create ECR repository
aws ecr create-repository --repository-name flight-mock-api --region us-east-1

# Build and tag image
docker build -t flight-mock-api .
docker tag flight-mock-api:latest <account-id>.dkr.ecr.us-east-1.amazonaws.com/flight-mock-api:latest

# Push to ECR
docker push <account-id>.dkr.ecr.us-east-1.amazonaws.com/flight-mock-api:latest
```

### 2. Create ECS Task Definition

Create a file `task-definition.json`:

```json
{
  "family": "flight-mock-api",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "256",
  "memory": "512",
  "containerDefinitions": [
    {
      "name": "flight-mock-api",
      "image": "<account-id>.dkr.ecr.us-east-1.amazonaws.com/flight-mock-api:latest",
      "portMappings": [
        {
          "containerPort": 5000,
          "protocol": "tcp"
        }
      ],
      "environment": [
        {"name": "PORT", "value": "5000"},
        {"name": "ROWS_PER_REQUEST", "value": "100"}
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/flight-mock-api",
          "awslogs-region": "us-east-1",
          "awslogs-stream-prefix": "ecs"
        }
      },
      "healthCheck": {
        "command": ["CMD-SHELL", "curl -f http://localhost:5000/health || exit 1"],
        "interval": 30,
        "timeout": 5,
        "retries": 3,
        "startPeriod": 10
      }
    }
  ]
}
```

Register the task definition:
```bash
aws ecs register-task-definition --cli-input-json file://task-definition.json
```

### 3. Create ECS Service

```bash
aws ecs create-service \
  --cluster your-cluster-name \
  --service-name flight-mock-api \
  --task-definition flight-mock-api \
  --desired-count 1 \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[subnet-xxx],securityGroups=[sg-xxx],assignPublicIp=ENABLED}"
```

### 4. Set Up Application Load Balancer (Optional)

For production use, add an ALB:
- Create target group pointing to ECS service
- Configure health check to `/health`
- Update ECS service to use load balancer

## 📊 Monitoring

### CloudWatch Logs

View API logs:
```bash
aws logs tail /ecs/flight-mock-api --follow
```

### Metrics to Monitor

- Request rate (requests/minute)
- Response time (p50, p95, p99)
- Error rate (4xx, 5xx)
- Health check status
- Memory/CPU utilization

### Setting Up Alarms

```bash
# Create CloudWatch alarm for unhealthy status
aws cloudwatch put-metric-alarm \
  --alarm-name flight-mock-api-unhealthy \
  --alarm-description "Alert if mock API becomes unhealthy" \
  --metric-name HealthCheckStatus \
  --namespace AWS/ECS \
  --statistic Average \
  --period 60 \
  --threshold 1 \
  --comparison-operator LessThanThreshold \
  --evaluation-periods 2
```

## 🧹 Cleanup

### Docker
```bash
docker-compose down
docker rmi flight-mock-api
```

### AWS ECS
```bash
# Delete service
aws ecs delete-service --cluster your-cluster --service flight-mock-api --force

# Deregister task definition
aws ecs deregister-task-definition --task-definition flight-mock-api:1

# Delete ECR repository
aws ecr delete-repository --repository-name flight-mock-api --force
```

## 🤝 Support

For issues or questions:
1. Check the logs: `docker-compose logs -f` or `aws logs tail /ecs/flight-mock-api`
2. Verify the API is running: `curl http://localhost:5000/health`
3. Review the API documentation: `curl http://localhost:5000/`

## 📝 License

MIT License - see LICENSE file for details
