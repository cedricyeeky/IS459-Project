# Docker Image Deployment Guide

This guide explains how to build and deploy Docker images for your Flight Delays Pipeline.

## Prerequisites

Before running the deployment script, ensure:

1. ✅ **Docker** is installed and running
2. ✅ **AWS CLI** is configured with valid credentials
3. ✅ **Terraform** has been applied at least once:
   ```bash
   cd terraform
   terraform init
   terraform apply
   ```

## Quick Start

### Deploy Everything (Mock API + Scraper)

```bash
./deploy-docker-images.sh
```

This will:
- Build Mock API Docker image
- Build Scraper Docker image
- Push both to ECR
- Restart ECS services

### Deploy with Lambda Scraped Processor

```bash
./deploy-docker-images.sh --with-lambda
```

### Skip ECS Service Restart

```bash
./deploy-docker-images.sh --skip-restart
```

## What Gets Built & Pushed

| Component | Source Location | Target |
|-----------|----------------|--------|
| **Mock API** | `terraform/modules/mock_api_ecs/src/` | ECR (ECS) |
| **Scraper** | `terraform/modules/scraper_ecs/src/` | ECR (ECS Task) |
| **Lambda Processor** | `terraform/modules/lambda_scraped_processed/src/` | ECR (Lambda) |

## Typical Workflow

### First Time Deployment

```bash
# 1. Apply Terraform (creates ECR repos + infrastructure)
cd terraform
terraform apply

# 2. Build and push Docker images
cd ..
./deploy-docker-images.sh

# 3. Wait for ECS services to start
aws ecs describe-services \
  --cluster $(cd terraform && terraform output -raw ecs_cluster_name) \
  --services $(cd terraform && terraform output -raw mock_api_service_name)
```

### After Code Changes

```bash
# Just rebuild and push
./deploy-docker-images.sh
```

The script will automatically:
- Rebuild changed images
- Push to ECR
- Trigger ECS service redeployment

## Monitoring Deployment

### Check ECS Service Status
```bash
aws ecs describe-services \
  --cluster flight-mock-api-dev-cluster \
  --services flight-mock-api-dev-mock-api-service \
  --query 'services[0].deployments'
```

### View Mock API Logs
```bash
aws logs tail /ecs/flight-mock-api-dev/mock-api --follow
```

### View Scraper Logs
```bash
aws logs tail /ecs/flight-mock-api-dev/scraper --follow
```

### Get Mock API Endpoint
```bash
cd terraform
terraform output alb_url
```

## Troubleshooting

### "Docker daemon is not running"
Start Docker Desktop or Docker daemon:
```bash
# macOS
open -a Docker

# Linux
sudo systemctl start docker
```

### "Terraform state not found"
Run terraform apply first:
```bash
cd terraform
terraform init
terraform apply
```

### "Failed to push to ECR"
Check AWS credentials:
```bash
aws sts get-caller-identity
```

### ECS Service Won't Start
Check task logs:
```bash
aws ecs describe-tasks \
  --cluster <cluster-name> \
  --tasks $(aws ecs list-tasks --cluster <cluster-name> --query 'taskArns[0]' --output text)
```

## Manual Deployment (Alternative)

If you prefer manual control:

### Mock API
```bash
cd terraform/modules/mock_api_ecs/src

# Get ECR URL
ECR_URL=$(cd ../../../ && terraform output -raw mock_api_ecr_repository_url)

# Login
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin $ECR_URL

# Build and push
docker build --platform linux/amd64 -t mock-api:latest .
docker tag mock-api:latest $ECR_URL:latest
docker push $ECR_URL:latest
```

### Scraper
```bash
cd terraform/modules/scraper_ecs/src

# Get ECR URL
ECR_URL=$(cd ../../../ && terraform output -raw scraper_ecr_repository_url)

# Build and push
docker build --platform linux/amd64 -t scraper:latest .
docker tag scraper:latest $ECR_URL:latest
docker push $ECR_URL:latest
```

## Script Options

```bash
./deploy-docker-images.sh [OPTIONS]

Options:
  --with-lambda     Also build and push Lambda scraped processor image
  --skip-restart    Skip restarting ECS services after push
  --help            Show help message
```

## Common Scenarios

### Scenario 1: Fresh Deployment
```bash
cd terraform
terraform apply
cd ..
./deploy-docker-images.sh
```

### Scenario 2: Update Mock API Code
```bash
# Edit code in terraform/modules/mock_api_ecs/src/
./deploy-docker-images.sh
```

### Scenario 3: Update Lambda Function
```bash
# Edit code in terraform/modules/lambda_scraped_processed/src/
./deploy-docker-images.sh --with-lambda --skip-restart
```

### Scenario 4: Update Scraper Only
```bash
# Edit scraper code
./deploy-docker-images.sh
```

## Notes

- **ECS Services**: Will automatically pull new images when restarted
- **Scraper**: Runs on EventBridge schedule (every 15 minutes by default)
- **Lambda**: Updated immediately when pushed
- **Build Time**: Approximately 5-10 minutes for all images
- **Platform**: Always builds for `linux/amd64` (required for AWS Lambda/ECS)

## Support

For issues:
1. Check script output for error messages
2. Verify AWS credentials: `aws sts get-caller-identity`
3. Verify Docker is running: `docker info`
4. Check Terraform state: `cd terraform && terraform show`
