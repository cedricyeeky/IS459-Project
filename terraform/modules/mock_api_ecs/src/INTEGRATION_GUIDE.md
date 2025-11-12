# Mock API Integration Guide for ECS Scraper

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                   FLIGHT DATA PIPELINE WITH MOCK API                │
└─────────────────────────────────────────────────────────────────────┘

┌──────────────────┐         ┌──────────────────┐
│  EventBridge     │         │  Mock Flight API │
│  (Every 15 min)  │────────▶│  (ECS Service)   │
└────────┬─────────┘         │  Port: 5000      │
         │                   └────────┬─────────┘
         │                            │
         ▼                            │
┌──────────────────┐                  │
│  ECS Scraper     │◀─────────────────┘
│  (Fargate Task)  │    HTTP GET /api/v1/flights/realtime
└────────┬─────────┘
         │
         │ Upload JSON
         ▼
┌──────────────────┐
│  S3 Raw Bucket   │
│  /scraped/       │
│  /flights/       │
│  YYYY/MM/DD/     │
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│  Glue Jobs       │
│  (Cleaning &     │
│   Features)      │
└──────────────────┘
```

## Step 1: Deploy Mock API to ECS

### 1.1 Create ECR Repository

```bash
# Create repository
aws ecr create-repository \
  --repository-name flight-mock-api \
  --region us-east-1

# Get repository URI
ECR_URI=$(aws ecr describe-repositories \
  --repository-names flight-mock-api \
  --query 'repositories[0].repositoryUri' \
  --output text)

echo "ECR URI: $ECR_URI"
```

### 1.2 Build and Push Docker Image

```bash
# Navigate to mock_api directory
cd mock_api

# Authenticate Docker to ECR
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin $ECR_URI

# Build image
docker build -t flight-mock-api .

# Tag image
docker tag flight-mock-api:latest $ECR_URI:latest

# Push to ECR
docker push $ECR_URI:latest
```

### 1.3 Create ECS Cluster (if not exists)

```bash
aws ecs create-cluster \
  --cluster-name flight-data-cluster \
  --region us-east-1
```

### 1.4 Create ECS Task Definition

Create `task-definition-mock-api.json`:

```json
{
  "family": "flight-mock-api",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "256",
  "memory": "512",
  "executionRoleArn": "arn:aws:iam::{ACCOUNT_ID}:role/ecsTaskExecutionRole",
  "containerDefinitions": [
    {
      "name": "flight-mock-api",
      "image": "{ECR_URI}:latest",
      "portMappings": [
        {
          "containerPort": 5000,
          "protocol": "tcp"
        }
      ],
      "environment": [
        {"name": "PORT", "value": "5000"},
        {"name": "ROWS_PER_REQUEST", "value": "100"},
        {"name": "DEBUG", "value": "False"}
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/flight-mock-api",
          "awslogs-region": "us-east-1",
          "awslogs-stream-prefix": "ecs",
          "awslogs-create-group": "true"
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
# Replace placeholders
sed -i "s/{ACCOUNT_ID}/$(aws sts get-caller-identity --query Account --output text)/g" task-definition-mock-api.json
sed -i "s|{ECR_URI}|$ECR_URI|g" task-definition-mock-api.json

# Register task definition
aws ecs register-task-definition \
  --cli-input-json file://task-definition-mock-api.json
```

### 1.5 Create ECS Service

```bash
# Get VPC and subnet information
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=isDefault,Values=true" --query 'Vpcs[0].VpcId' --output text)
SUBNET_1=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" --query 'Subnets[0].SubnetId' --output text)
SUBNET_2=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" --query 'Subnets[1].SubnetId' --output text)

# Create security group for Mock API
SG_MOCK_API=$(aws ec2 create-security-group \
  --group-name flight-mock-api-sg \
  --description "Security group for Flight Mock API" \
  --vpc-id $VPC_ID \
  --query 'GroupId' \
  --output text)

# Allow inbound on port 5000 from within VPC
aws ec2 authorize-security-group-ingress \
  --group-id $SG_MOCK_API \
  --protocol tcp \
  --port 5000 \
  --cidr 10.0.0.0/8

# Create ECS service
aws ecs create-service \
  --cluster flight-data-cluster \
  --service-name flight-mock-api \
  --task-definition flight-mock-api \
  --desired-count 1 \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[$SUBNET_1,$SUBNET_2],securityGroups=[$SG_MOCK_API],assignPublicIp=ENABLED}"
```

### 1.6 Get Mock API URL

```bash
# Wait for task to start
sleep 30

# Get task ARN
TASK_ARN=$(aws ecs list-tasks \
  --cluster flight-data-cluster \
  --service-name flight-mock-api \
  --query 'taskArns[0]' \
  --output text)

# Get task details to find IP
TASK_IP=$(aws ecs describe-tasks \
  --cluster flight-data-cluster \
  --tasks $TASK_ARN \
  --query 'tasks[0].attachments[0].details[?name==`privateIPv4Address`].value' \
  --output text)

echo "Mock API URL: http://$TASK_IP:5000"

# Test the API
curl http://$TASK_IP:5000/health
```

## Step 2: Create ECS Scraper Task

### 2.1 Create Scraper Dockerfile

Create `Dockerfile.scraper`:

```dockerfile
FROM python:3.11-slim

WORKDIR /app

# Install dependencies
RUN pip install --no-cache-dir boto3

# Copy scraper script
COPY scraper_example.py .

# Run scraper
CMD ["python", "scraper_example.py"]
```

### 2.2 Build and Push Scraper Image

```bash
# Create ECR repository for scraper
aws ecr create-repository \
  --repository-name flight-scraper \
  --region us-east-1

# Get scraper repository URI
SCRAPER_ECR_URI=$(aws ecr describe-repositories \
  --repository-names flight-scraper \
  --query 'repositories[0].repositoryUri' \
  --output text)

# Build scraper image
docker build -f Dockerfile.scraper -t flight-scraper .

# Tag and push
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin $SCRAPER_ECR_URI

docker tag flight-scraper:latest $SCRAPER_ECR_URI:latest
docker push $SCRAPER_ECR_URI:latest
```

### 2.3 Create IAM Role for Scraper

```bash
# Create trust policy
cat > scraper-trust-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ecs-tasks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

# Create role
aws iam create-role \
  --role-name flight-scraper-task-role \
  --assume-role-policy-document file://scraper-trust-policy.json

# Create policy for S3 access
cat > scraper-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:PutObjectAcl"
      ],
      "Resource": "arn:aws:s3:::flight-delays-*-raw/scraped/*"
    }
  ]
}
EOF

# Attach policy
aws iam put-role-policy \
  --role-name flight-scraper-task-role \
  --policy-name S3WritePolicy \
  --policy-document file://scraper-policy.json
```

### 2.4 Create Scraper Task Definition

Create `task-definition-scraper.json`:

```json
{
  "family": "flight-scraper",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "256",
  "memory": "512",
  "executionRoleArn": "arn:aws:iam::{ACCOUNT_ID}:role/ecsTaskExecutionRole",
  "taskRoleArn": "arn:aws:iam::{ACCOUNT_ID}:role/flight-scraper-task-role",
  "containerDefinitions": [
    {
      "name": "flight-scraper",
      "image": "{SCRAPER_ECR_URI}:latest",
      "environment": [
        {"name": "MOCK_API_URL", "value": "http://{TASK_IP}:5000"},
        {"name": "S3_BUCKET", "value": "flight-delays-dev-raw"},
        {"name": "S3_PREFIX", "value": "scraped/flights/"},
        {"name": "BATCH_SIZE", "value": "100"}
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/flight-scraper",
          "awslogs-region": "us-east-1",
          "awslogs-stream-prefix": "ecs",
          "awslogs-create-group": "true"
        }
      }
    }
  ]
}
```

Register:

```bash
# Replace placeholders
sed -i "s/{ACCOUNT_ID}/$(aws sts get-caller-identity --query Account --output text)/g" task-definition-scraper.json
sed -i "s|{SCRAPER_ECR_URI}|$SCRAPER_ECR_URI|g" task-definition-scraper.json
sed -i "s/{TASK_IP}/$TASK_IP/g" task-definition-scraper.json

# Register
aws ecs register-task-definition \
  --cli-input-json file://task-definition-scraper.json
```

## Step 3: Create EventBridge Schedule

### 3.1 Create EventBridge Scheduler Execution Role

```bash
# Create trust policy for EventBridge Scheduler
cat > scheduler-trust-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "scheduler.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

# Create role
aws iam create-role \
  --role-name flight-scraper-scheduler-role \
  --assume-role-policy-document file://scheduler-trust-policy.json

# Attach ECS task execution policy
cat > scheduler-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ecs:RunTask"
      ],
      "Resource": "arn:aws:ecs:us-east-1:{ACCOUNT_ID}:task-definition/flight-scraper:*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "iam:PassRole"
      ],
      "Resource": [
        "arn:aws:iam::{ACCOUNT_ID}:role/ecsTaskExecutionRole",
        "arn:aws:iam::{ACCOUNT_ID}:role/flight-scraper-task-role"
      ]
    }
  ]
}
EOF

sed -i "s/{ACCOUNT_ID}/$(aws sts get-caller-identity --query Account --output text)/g" scheduler-policy.json

aws iam put-role-policy \
  --role-name flight-scraper-scheduler-role \
  --policy-name ECSRunTaskPolicy \
  --policy-document file://scheduler-policy.json
```

### 3.2 Create Schedule (Every 15 Minutes)

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

aws scheduler create-schedule \
  --name flight-scraper-schedule \
  --schedule-expression "rate(15 minutes)" \
  --flexible-time-window Mode=OFF \
  --target "{
    \"Arn\": \"arn:aws:ecs:us-east-1:$ACCOUNT_ID:cluster/flight-data-cluster\",
    \"RoleArn\": \"arn:aws:iam::$ACCOUNT_ID:role/flight-scraper-scheduler-role\",
    \"EcsParameters\": {
      \"TaskDefinitionArn\": \"arn:aws:ecs:us-east-1:$ACCOUNT_ID:task-definition/flight-scraper\",
      \"LaunchType\": \"FARGATE\",
      \"NetworkConfiguration\": {
        \"awsvpcConfiguration\": {
          \"Subnets\": [\"$SUBNET_1\", \"$SUBNET_2\"],
          \"SecurityGroups\": [\"$SG_MOCK_API\"],
          \"AssignPublicIp\": \"ENABLED\"
        }
      }
    }
  }"
```

## Step 4: Test the Integration

### 4.1 Manually Trigger Scraper

```bash
# Run scraper task manually
aws ecs run-task \
  --cluster flight-data-cluster \
  --task-definition flight-scraper \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[$SUBNET_1,$SUBNET_2],securityGroups=[$SG_MOCK_API],assignPublicIp=ENABLED}"
```

### 4.2 Check Logs

```bash
# Get scraper task ARN
SCRAPER_TASK=$(aws ecs list-tasks \
  --cluster flight-data-cluster \
  --family flight-scraper \
  --query 'taskArns[0]' \
  --output text)

# View logs
aws logs tail /ecs/flight-scraper --follow
```

### 4.3 Verify S3 Data

```bash
# List scraped files
aws s3 ls s3://flight-delays-dev-raw/scraped/flights/ --recursive

# Download and inspect a file
aws s3 cp s3://flight-delays-dev-raw/scraped/flights/2024/11/04/$(aws s3 ls s3://flight-delays-dev-raw/scraped/flights/2024/11/04/ --recursive | tail -1 | awk '{print $4}') - | jq '.summary_statistics'
```

## Step 5: Monitor the Pipeline

### 5.1 CloudWatch Dashboard

Create a dashboard to monitor:
- Mock API health check status
- Scraper task execution count
- S3 upload success rate
- API response times

### 5.2 Set Up Alarms

```bash
# Alarm for scraper failures
aws cloudwatch put-metric-alarm \
  --alarm-name flight-scraper-failures \
  --alarm-description "Alert on scraper task failures" \
  --metric-name TasksRunning \
  --namespace AWS/ECS \
  --statistic Average \
  --period 900 \
  --threshold 0 \
  --comparison-operator LessThanThreshold \
  --evaluation-periods 2 \
  --dimensions Name=ServiceName,Value=flight-mock-api Name=ClusterName,Value=flight-data-cluster
```

## Troubleshooting

### Mock API not accessible from scraper

**Issue**: Scraper can't connect to Mock API

**Solution**:
1. Check security groups allow traffic between tasks
2. Verify both tasks are in the same VPC
3. Use AWS Service Discovery for dynamic DNS
4. Check CloudWatch logs for connection errors

### Scraper not uploading to S3

**Issue**: Files not appearing in S3

**Solution**:
1. Verify IAM role has S3 write permissions
2. Check S3 bucket name matches configuration
3. Review scraper logs for upload errors
4. Ensure bucket exists and is in the same region

### EventBridge schedule not triggering

**Issue**: Tasks not running every 15 minutes

**Solution**:
1. Verify schedule is enabled: `aws scheduler get-schedule --name flight-scraper-schedule`
2. Check scheduler role has ECS permissions
3. Review EventBridge logs in CloudWatch
4. Ensure task definition is active

## Cost Optimization

### Estimated Monthly Costs

| Resource | Configuration | Monthly Cost |
|----------|--------------|--------------|
| Mock API (ECS) | 1 task, 0.25 vCPU, 0.5 GB, 24/7 | ~$15 |
| Scraper (ECS) | 96 runs/day, 0.25 vCPU, 0.5 GB, 5 min | ~$3 |
| S3 Storage | 10 GB scraped data | ~$0.23 |
| CloudWatch Logs | 5 GB/month | ~$2.50 |
| EventBridge | 2,880 invocations | ~$0.00 |
| **Total** | | **~$20.73/month** |

### Cost Reduction Tips

1. **Use Spot instances** for scraper tasks (50-70% savings)
2. **Reduce scraper frequency** to 30 minutes (50% savings on scraper)
3. **Implement S3 Lifecycle policies** to archive old data
4. **Use Fargate Spot** for non-critical workloads
5. **Set CloudWatch log retention** to 7 days

## Next Steps

1. ✅ Deploy Mock API to ECS
2. ✅ Deploy Scraper to ECS
3. ✅ Set up EventBridge schedule
4. ✅ Verify data flow to S3
5. ⏭️ Update Glue jobs to process scraped data
6. ⏭️ Set up monitoring and alerts
7. ⏭️ Implement error handling and retries
8. ⏭️ Add data quality checks

Your mock API is now ready to simulate realistic flight data for your reliability analysis! 🚀✈️
