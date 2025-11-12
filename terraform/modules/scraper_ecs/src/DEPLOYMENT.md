# Data Scraper Deployment Guide

Complete guide for deploying the EventBridge + ECS scraper to collect data from Mock API.

## Prerequisites

- AWS CLI configured with credentials (IAM user: flight-delay-project)
- Docker installed and running
- Terraform already applied (infrastructure created)
- Mock API already running on ECS

## Architecture Overview

```
┌─────────────────┐
│  EventBridge    │  Triggers every 15 minutes
│   Schedule      │
└────────┬────────┘
         │
         ↓
┌─────────────────┐
│   ECS Fargate   │  Runs scraper container
│     Scraper     │
└────────┬────────┘
         │
         ↓
┌─────────────────┐
│    Mock API     │  Fetches weather + flights
│      (ALB)      │
└────────┬────────┘
         │
         ↓
┌─────────────────┐
│   S3 Raw Data   │  Stores JSON files
│     Bucket      │  scraped/{type}/YYYY/MM/DD/HH/
└─────────────────┘
```

## Step 1: Build Scraper Docker Image

```bash
# Navigate to scraper directory
cd /Users/jordianojr/Desktop/BDA_Project/IS459-Project/scraper

# Build Docker image for AMD64 (ECS requirement)
docker build --platform linux/amd64 -t scraper:latest .
```

**Expected output:**
```
[+] Building 45.2s (12/12) FINISHED
 => [internal] load build definition from Dockerfile
 => => transferring dockerfile: 1.02kB
 => [internal] load .dockerignore
 => [builder 1/3] FROM docker.io/library/python:3.11-slim
 => [builder 2/3] COPY requirements.txt .
 => [builder 3/3] RUN pip install --no-cache-dir --user -r requirements.txt
 => [stage-1 4/5] COPY --from=builder /root/.local /root/.local
 => [stage-1 5/5] COPY app.py .
 => exporting to image
 => => naming to docker.io/library/scraper:latest
```

## Step 2: Authenticate with ECR

```bash
# Get your account ID and region from terraform output
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin \
  820242928352.dkr.ecr.us-east-1.amazonaws.com
```

**Expected output:**
```
Login Succeeded
```

## Step 3: Tag and Push to ECR

```bash
# Get ECR repository URL from terraform output
export SCRAPER_ECR_URL=$(cd ../terraform/longterm && terraform output -raw scraper_ecr_repository_url)

# Tag the image
docker tag scraper:latest ${SCRAPER_ECR_URL}:latest

# Push to ECR
docker push ${SCRAPER_ECR_URL}:latest
```

**Expected output:**
```
The push refers to repository [820242928352.dkr.ecr.us-east-1.amazonaws.com/flight-mock-api-prod-scraper]
a1b2c3d4e5f6: Pushed
...
latest: digest: sha256:abc123... size: 1234
```

## Step 4: Verify Infrastructure

```bash
cd ../terraform/longterm

# Check that scraper resources were created
terraform output | grep scraper
```

**Expected outputs:**
```
scraper_ecr_repository_url = "820242928352.dkr.ecr.us-east-1.amazonaws.com/flight-mock-api-prod-scraper"
scraper_log_group = "/ecs/flight-mock-api-prod/scraper"
scraper_schedule = "rate(15 minutes)"
scraper_task_definition_arn = "arn:aws:ecs:us-east-1:820242928352:task-definition/flight-mock-api-prod-scraper:1"
eventbridge_rule_name = "flight-mock-api-prod-scraper-schedule"
```

## Step 5: Manually Test Scraper (Optional)

Before waiting for the schedule, test the scraper manually:

```bash
# Get values from terraform
export CLUSTER_NAME=$(terraform output -raw ecs_cluster_name)
export TASK_DEF=$(terraform output -raw scraper_task_definition_arn)
export PRIVATE_SUBNETS=$(terraform output -json private_subnet_ids | jq -r '.[]' | paste -sd "," -)
export SCRAPER_SG=$(terraform output -raw | grep scraper_security_group_id | cut -d'"' -f2)

# Run task manually
aws ecs run-task \
  --cluster ${CLUSTER_NAME} \
  --task-definition ${TASK_DEF} \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[${PRIVATE_SUBNETS}],securityGroups=[${SCRAPER_SG}],assignPublicIp=DISABLED}" \
  --region us-east-1
```

**Expected output:**
```json
{
    "tasks": [
        {
            "taskArn": "arn:aws:ecs:us-east-1:820242928352:task/flight-mock-api-prod-cluster/abc123...",
            "lastStatus": "PROVISIONING",
            "desiredStatus": "RUNNING",
            ...
        }
    ]
}
```

## Step 6: Monitor Scraper Execution

### Watch Live Logs

```bash
# Tail scraper logs
aws logs tail /ecs/flight-mock-api-prod/scraper --follow --region us-east-1
```

**Expected log output:**
```
2025-11-10 14:30:52 - INFO - ======================================================================
2025-11-10 14:30:52 - INFO - Starting Mock API Data Scraper
2025-11-10 14:30:52 - INFO - ======================================================================
2025-11-10 14:30:52 - INFO - API Endpoint: http://flight-mock-api-prod-alb-2052111428.us-east-1.elb.amazonaws.com
2025-11-10 14:30:52 - INFO - S3 Bucket: flight-mock-api-prod-raw
2025-11-10 14:30:52 - INFO - Checking API health...
2025-11-10 14:30:53 - INFO - API is healthy (version: v1)
2025-11-10 14:30:53 - INFO - Fetching weather data...
2025-11-10 14:30:54 - INFO - Successfully fetched 480 weather observations
2025-11-10 14:30:54 - INFO - Uploading weather data to S3...
2025-11-10 14:30:55 - INFO - Successfully uploaded weather data
2025-11-10 14:30:55 - INFO - Fetching realtime flights...
2025-11-10 14:30:56 - INFO - Successfully fetched 245 realtime flights
2025-11-10 14:30:56 - INFO - Uploading flights data to S3...
2025-11-10 14:30:57 - INFO - Successfully uploaded flights data
2025-11-10 14:30:57 - INFO - ======================================================================
2025-11-10 14:30:57 - INFO - Scraper execution completed
2025-11-10 14:30:57 - INFO - Successful uploads: 2/2
2025-11-10 14:30:57 - INFO - ======================================================================
```

### View Recent Logs

```bash
# Last 30 minutes of logs
aws logs tail /ecs/flight-mock-api-prod/scraper --since 30m --region us-east-1
```

### Check ECS Task Status

```bash
# List running scraper tasks
aws ecs list-tasks \
  --cluster flight-mock-api-prod-cluster \
  --family flight-mock-api-prod-scraper \
  --desired-status RUNNING \
  --region us-east-1

# List recently stopped tasks
aws ecs list-tasks \
  --cluster flight-mock-api-prod-cluster \
  --family flight-mock-api-prod-scraper \
  --desired-status STOPPED \
  --max-results 5 \
  --region us-east-1
```

## Step 7: Verify Data in S3

```bash
# Get S3 bucket name
export RAW_BUCKET=$(cd ../terraform/longterm && terraform output -raw raw_bucket_name)

# List all scraped data
aws s3 ls s3://${RAW_BUCKET}/scraped/ --recursive --region us-east-1

# List today's weather data
TODAY=$(date +%Y/%m/%d)
aws s3 ls s3://${RAW_BUCKET}/scraped/weather/${TODAY}/ --recursive

# List today's flights data
aws s3 ls s3://${RAW_BUCKET}/scraped/flights/${TODAY}/ --recursive
```

**Expected output:**
```
2025-11-10 14:30:57    125678 scraped/weather/2025/11/10/14/weather_20251110_143052.json
2025-11-10 14:30:57     89432 scraped/flights/2025/11/10/14/flights_20251110_143052.json
2025-11-10 14:45:58    126102 scraped/weather/2025/11/10/14/weather_20251110_144553.json
2025-11-10 14:45:58     90128 scraped/flights/2025/11/10/14/flights_20251110_144553.json
```

### Download and Inspect a File

```bash
# Download latest weather file
LATEST_WEATHER=$(aws s3 ls s3://${RAW_BUCKET}/scraped/weather/ --recursive | sort | tail -1 | awk '{print $4}')
aws s3 cp s3://${RAW_BUCKET}/${LATEST_WEATHER} - | jq '.' | head -100
```

**Expected structure:**
```json
{
  "observations": [
    {
      "obs_id": "JFK_202511101430",
      "valid_time_gmt": 1762801888,
      "observation_time": "2025-11-10T14:30:00",
      "airport_code": "JFK",
      "airport_city": "New York",
      "wx_phrase": "Partly Cloudy",
      "temp": 67,
      "precip_hrly": 0.0,
      "snow_hrly": 0.0,
      "wspd": 12,
      "clds": "SCT",
      "rh": 65,
      "vis": 10.0,
      ...
    }
  ],
  "metadata": {...}
}
```

## Step 8: Monitor EventBridge Schedule

```bash
# Check EventBridge rule
aws events describe-rule \
  --name flight-mock-api-prod-scraper-schedule \
  --region us-east-1

# Check rule targets
aws events list-targets-by-rule \
  --rule flight-mock-api-prod-scraper-schedule \
  --region us-east-1
```

## Verification Checklist

- [ ] Scraper Docker image built successfully
- [ ] Image pushed to ECR
- [ ] Terraform outputs show scraper resources
- [ ] Manual scraper run completed successfully
- [ ] Logs show successful data fetch and upload
- [ ] S3 bucket contains scraped data files
- [ ] EventBridge rule is enabled
- [ ] Data files have correct folder structure
- [ ] JSON data has proper schema

## Common Issues

### Issue: Scraper fails with "API health check failed"

**Solution:**
```bash
# Check if Mock API is running
export ALB_URL=$(cd ../terraform/longterm && terraform output -raw alb_url)
curl ${ALB_URL}/health

# Check Mock API logs
aws logs tail /ecs/flight-mock-api-prod/mock-api --since 10m
```

### Issue: "S3 access denied" error

**Solution:**
```bash
# Verify scraper task role has S3 permissions
aws iam get-role-policy \
  --role-name flight-mock-api-prod-scraper-task-role \
  --policy-name flight-mock-api-prod-scraper-s3-policy
```

### Issue: Scraper not running on schedule

**Solution:**
```bash
# Check EventBridge rule is enabled
aws events describe-rule --name flight-mock-api-prod-scraper-schedule

# Check EventBridge execution history (CloudWatch Events)
aws cloudwatch get-metric-statistics \
  --namespace AWS/Events \
  --metric-name TriggeredRules \
  --dimensions Name=RuleName,Value=flight-mock-api-prod-scraper-schedule \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 900 \
  --statistics Sum
```

### Issue: Container fails to start

**Solution:**
```bash
# Check ECR image exists
aws ecr describe-images \
  --repository-name flight-mock-api-prod-scraper \
  --region us-east-1

# Check task definition
aws ecs describe-task-definition \
  --task-definition flight-mock-api-prod-scraper

# Check stopped tasks for errors
aws ecs describe-tasks \
  --cluster flight-mock-api-prod-cluster \
  --tasks $(aws ecs list-tasks --cluster flight-mock-api-prod-cluster --family flight-mock-api-prod-scraper --desired-status STOPPED --max-results 1 --query 'taskArns[0]' --output text)
```

## Next Steps

After successful deployment:

1. **Monitor for 1 hour** - Verify 4 scraper runs complete successfully
2. **Check data quality** - Inspect JSON files for schema correctness
3. **Set up alerts** - Create CloudWatch alarms for scraper failures
4. **Document data schema** - Add data dictionary for downstream consumers
5. **Plan data processing** - Design AWS Glue jobs for data transformation

## Cleanup (If Needed)

To disable the scraper without destroying infrastructure:

```bash
# Disable EventBridge rule
aws events disable-rule \
  --name flight-mock-api-prod-scraper-schedule \
  --region us-east-1
```

To completely remove scraper resources:

```bash
cd ../terraform/longterm

# Comment out the scraper module in main.tf
# Then apply
terraform apply
```

## Support

For issues or questions:
- Check CloudWatch logs first
- Review this guide's troubleshooting section
- Verify infrastructure with `terraform output`
