# Mock API Data Scraper

Automated data collection service that fetches weather and realtime flight data from the Mock API and stores it in S3.

## Overview

This scraper is deployed as an ECS Fargate task, triggered by EventBridge on a schedule (default: every 15 minutes). It calls two endpoints:

- `GET /api/v1/weather` - Weather observations
- `GET /api/v1/flights/realtime` - Realtime flight data

Data is uploaded to S3 in JSON format with timestamp-based folder structure.

## Features

- **Scheduled Execution**: Runs automatically via EventBridge (default: every 15 minutes)
- **Health Check**: Verifies API health before scraping
- **Timestamp-based Storage**: Organizes data by date/time for easy querying
- **Error Handling**: Comprehensive logging and error handling
- **S3 Metadata**: Stores record counts and timestamps in S3 object metadata

## Architecture

```
EventBridge (Schedule) 
    ↓
ECS Fargate Task (Scraper)
    ↓
Mock API (ALB)
    ↓
S3 Raw Bucket
```

## S3 Folder Structure

Data is stored in the raw S3 bucket with the following structure:

```
s3://{bucket-name}/scraped/
├── weather/
│   └── YYYY/
│       └── MM/
│           └── DD/
│               └── HH/
│                   └── weather_YYYYMMDD_HHMMSS.json
└── flights/
    └── YYYY/
        └── MM/
            └── DD/
                └── HH/
                    └── flights_YYYYMMDD_HHMMSS.json
```

**Example:**
- `s3://flight-mock-api-prod-raw/scraped/weather/2025/11/10/14/weather_20251110_143052.json`
- `s3://flight-mock-api-prod-raw/scraped/flights/2025/11/10/14/flights_20251110_143052.json`

## Environment Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `API_ENDPOINT` | Mock API base URL (ALB DNS) | `http://localhost:5200` | Yes |
| `S3_BUCKET` | S3 bucket name for raw data | - | Yes |
| `AWS_REGION` | AWS region | `us-east-1` | No |
| `REQUEST_TIMEOUT` | API request timeout (seconds) | `30` | No |

## IAM Permissions

The scraper task role requires:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:PutObjectAcl",
        "s3:GetObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::bucket-name",
        "arn:aws:s3:::bucket-name/*"
      ]
    }
  ]
}
```

## Building and Deploying

### 1. Build Docker Image

```bash
# Build for ECS (AMD64 platform)
docker build --platform linux/amd64 -t scraper:latest .

# Test locally (requires AWS credentials and mock API running)
docker run -e API_ENDPOINT=http://host.docker.internal:5200 \
           -e S3_BUCKET=my-bucket \
           -e AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID \
           -e AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY \
           -e AWS_REGION=us-east-1 \
           scraper:latest
```

### 2. Push to ECR

```bash
# Authenticate with ECR
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin \
  820242928352.dkr.ecr.us-east-1.amazonaws.com

# Tag image
docker tag scraper:latest \
  820242928352.dkr.ecr.us-east-1.amazonaws.com/flight-mock-api-prod-scraper:latest

# Push image
docker push \
  820242928352.dkr.ecr.us-east-1.amazonaws.com/flight-mock-api-prod-scraper:latest
```

### 3. Deploy with Terraform

The scraper infrastructure is managed in `terraform/longterm/scraper/`:

```bash
cd terraform/longterm

# Initialize Terraform
terraform init

# Apply configuration (includes scraper module)
terraform apply
```

## Manual Testing

### Trigger Scraper Manually

```bash
# Run the scraper task manually (for testing)
aws ecs run-task \
  --cluster flight-mock-api-prod-cluster \
  --task-definition flight-mock-api-prod-scraper \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[subnet-xxx],securityGroups=[sg-xxx],assignPublicIp=DISABLED}" \
  --region us-east-1
```

### View Logs

```bash
# Tail scraper logs
aws logs tail /ecs/flight-mock-api-prod/scraper --follow --region us-east-1

# Get recent logs
aws logs tail /ecs/flight-mock-api-prod/scraper --since 30m --region us-east-1
```

### Check S3 Data

```bash
# List all scraped data
aws s3 ls s3://flight-mock-api-prod-raw/scraped/ --recursive

# List weather data for today
aws s3 ls s3://flight-mock-api-prod-raw/scraped/weather/2025/11/10/ --recursive

# Download and view a specific file
aws s3 cp s3://flight-mock-api-prod-raw/scraped/weather/2025/11/10/14/weather_20251110_143052.json - | jq .
```

## Monitoring

### CloudWatch Metrics

Monitor the scraper execution:

```bash
# Check EventBridge rule status
aws events describe-rule --name flight-mock-api-prod-scraper-schedule

# List recent ECS task executions
aws ecs list-tasks --cluster flight-mock-api-prod-cluster \
  --family flight-mock-api-prod-scraper \
  --desired-status STOPPED
```

### Log Analysis

The scraper logs include:

- **INFO**: Normal operations (fetch success, upload success)
- **WARNING**: Partial failures (one endpoint failed)
- **ERROR**: Critical failures (API down, S3 unavailable)

Example log output:

```
2025-11-10 14:30:52 - __main__ - INFO - ======================================================================
2025-11-10 14:30:52 - __main__ - INFO - Starting Mock API Data Scraper
2025-11-10 14:30:52 - __main__ - INFO - ======================================================================
2025-11-10 14:30:52 - __main__ - INFO - API Endpoint: http://flight-mock-api-prod-alb-xxx.us-east-1.elb.amazonaws.com
2025-11-10 14:30:52 - __main__ - INFO - S3 Bucket: flight-mock-api-prod-raw
2025-11-10 14:30:52 - __main__ - INFO - AWS Region: us-east-1
2025-11-10 14:30:52 - __main__ - INFO - Scrape timestamp: 2025-11-10T14:30:52.123456+00:00
2025-11-10 14:30:52 - __main__ - INFO - Checking API health at http://...
2025-11-10 14:30:53 - __main__ - INFO - API is healthy (version: v1)
2025-11-10 14:30:53 - __main__ - INFO - ----------------------------------------------------------------------
2025-11-10 14:30:53 - __main__ - INFO - Fetching weather data...
2025-11-10 14:30:53 - __main__ - INFO - Fetching weather data from http://.../api/v1/weather
2025-11-10 14:30:54 - __main__ - INFO - Successfully fetched 480 weather observations
2025-11-10 14:30:54 - __main__ - INFO - Uploading weather data to s3://flight-mock-api-prod-raw/scraped/weather/2025/11/10/14/weather_20251110_143052.json
2025-11-10 14:30:55 - __main__ - INFO - Successfully uploaded weather data to S3
2025-11-10 14:30:55 - __main__ - INFO - ----------------------------------------------------------------------
2025-11-10 14:30:55 - __main__ - INFO - Fetching realtime flights...
2025-11-10 14:30:55 - __main__ - INFO - Fetching realtime flights from http://.../api/v1/flights/realtime
2025-11-10 14:30:56 - __main__ - INFO - Successfully fetched 245 realtime flights
2025-11-10 14:30:56 - __main__ - INFO - Uploading flights data to s3://flight-mock-api-prod-raw/scraped/flights/2025/11/10/14/flights_20251110_143052.json
2025-11-10 14:30:57 - __main__ - INFO - Successfully uploaded flights data to S3
2025-11-10 14:30:57 - __main__ - INFO - ======================================================================
2025-11-10 14:30:57 - __main__ - INFO - Scraper execution completed
2025-11-10 14:30:57 - __main__ - INFO - Successful uploads: 2/2
2025-11-10 14:30:57 - __main__ - INFO - Failed uploads: 0/2
2025-11-10 14:30:57 - __main__ - INFO - ======================================================================
2025-11-10 14:30:57 - __main__ - INFO - Scraper completed successfully
```

## Schedule Configuration

The scraper schedule is controlled by the `scraper_schedule_expression` variable in Terraform:

```hcl
# Every 15 minutes (default)
scraper_schedule_expression = "rate(15 minutes)"

# Every hour
scraper_schedule_expression = "rate(1 hour)"

# Every 30 minutes
scraper_schedule_expression = "rate(30 minutes)"

# Using cron (every 15 minutes, 24/7)
scraper_schedule_expression = "cron(0/15 * * * ? *)"

# Using cron (every hour at minute 5, weekdays only)
scraper_schedule_expression = "cron(5 * ? * MON-FRI *)"
```

## Troubleshooting

### Scraper Not Running

1. Check EventBridge rule is enabled:
   ```bash
   aws events describe-rule --name flight-mock-api-prod-scraper-schedule
   ```

2. Check ECS task definition exists:
   ```bash
   aws ecs describe-task-definition --task-definition flight-mock-api-prod-scraper
   ```

3. Manually trigger to test:
   ```bash
   aws ecs run-task --cluster flight-mock-api-prod-cluster \
     --task-definition flight-mock-api-prod-scraper \
     --launch-type FARGATE \
     --network-configuration "awsvpcConfiguration={...}"
   ```

### API Connection Failed

1. Check mock API is healthy:
   ```bash
   curl http://flight-mock-api-prod-alb-xxx.us-east-1.elb.amazonaws.com/health
   ```

2. Check security group allows outbound HTTPS:
   ```bash
   aws ec2 describe-security-groups --group-ids sg-xxx
   ```

3. Verify scraper has network connectivity (check CloudWatch logs)

### S3 Upload Failed

1. Check IAM permissions on task role
2. Verify S3 bucket exists and is accessible
3. Check CloudWatch logs for specific error messages

### Container Fails to Start

1. Check ECR image exists:
   ```bash
   aws ecr describe-images --repository-name flight-mock-api-prod-scraper
   ```

2. Check task definition has correct environment variables
3. Review CloudWatch logs for startup errors

## Dependencies

- **boto3** (>=1.34.0): AWS SDK for Python
- **requests** (>=2.31.0): HTTP library for API calls

## Exit Codes

- `0`: Success - all data fetched and uploaded
- `1`: Failure - one or more operations failed

## License

Part of the Flight Delays Big Data Analytics Project.
