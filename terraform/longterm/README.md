# Mock Flight API - Long-Term ECS Deployment

This Terraform configuration deploys a production-ready, long-running Mock Flight API on AWS ECS with automatic scraping every 15 minutes.

## Architecture

- **ECS Fargate**: Runs mock API containers (2 instances for HA)
- **Application Load Balancer**: Public endpoint for API access
- **EventBridge Scheduler**: Triggers scraper every 15 minutes
- **S3**: Stores scraped flight data
- **CloudWatch**: Logs and monitoring
- **ECR**: Docker image registry

## Prerequisites

1. **AWS CLI** configured with appropriate credentials
2. **Terraform** >= 1.0 installed
3. **Docker** for building images
4. AWS account with permissions for ECS, VPC, ALB, S3, ECR, CloudWatch, EventBridge

## Quick Start

### 1. Configure Variables

```bash
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your settings
```

### 2. Initialize Terraform

```bash
terraform init
```

### 3. Review Plan

```bash
terraform plan
```

### 4. Deploy Infrastructure

```bash
terraform apply
```

This creates:
- VPC with public/private subnets (or uses existing)
- ECR repositories for Docker images
- S3 bucket for data storage (or uses existing)
- ECS cluster with Mock API service
- Application Load Balancer
- EventBridge schedule for scraper
- IAM roles and security groups
- CloudWatch log groups

### 5. Build and Push Docker Images

After infrastructure is created, push your Docker images:

```bash
# Get ECR login
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin $(terraform output -raw mock_api_ecr_repository_url)

# Build and push Mock API
cd ../../mock_api
docker build -t $(terraform output -raw mock_api_ecr_repository_url):latest -f Dockerfile .
docker push $(terraform output -raw mock_api_ecr_repository_url):latest

# Build and push Scraper
docker build -t $(terraform output -raw scraper_ecr_repository_url):latest -f Dockerfile.scraper .
docker push $(terraform output -raw scraper_ecr_repository_url):latest
```

### 6. Force Service Update

```bash
# Update Mock API service to use new image
aws ecs update-service \
  --cluster $(terraform output -raw ecs_cluster_name) \
  --service $(terraform output -raw mock_api_service_name) \
  --force-new-deployment \
  --region us-east-1
```

### 7. Test the Deployment

```bash
# Health check
curl $(terraform output -raw alb_url)/health

# Get flight data
curl $(terraform output -raw mock_api_endpoint)

# Check logs
aws logs tail $(terraform output -raw mock_api_log_group) --follow
```

## Configuration Options

### Network Configuration

**Use Existing VPC:**
```hcl
vpc_id = "vpc-xxxxx"
```

**Create New VPC:**
```hcl
vpc_id                = ""
vpc_cidr              = "10.0.0.0/16"
availability_zones    = ["us-east-1a", "us-east-1b"]
private_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
public_subnet_cidrs   = ["10.0.101.0/24", "10.0.102.0/24"]
single_nat_gateway    = true  # false for HA
```

### S3 Configuration

**Use Existing Bucket:**
```hcl
raw_bucket_name = "my-existing-bucket"
```

**Create New Bucket:**
```hcl
raw_bucket_name         = ""
raw_data_retention_days = 90
```

### Mock API Scaling

```hcl
mock_api_cpu           = 512    # 0.5 vCPU
mock_api_memory        = 1024   # 1 GB RAM
mock_api_desired_count = 2      # Number of tasks
```

### Scraper Schedule

```hcl
# Every 15 minutes (default)
scraper_schedule_expression = "rate(15 minutes)"

# Every 5 minutes
scraper_schedule_expression = "rate(5 minutes)"

# Every hour
scraper_schedule_expression = "rate(1 hour)"

# Every day at 2 AM UTC
scraper_schedule_expression = "cron(0 2 * * ? *)"
```

## Monitoring

### CloudWatch Logs

```bash
# Mock API logs
aws logs tail /ecs/flight-mock-api-dev/mock-api --follow

# Scraper logs
aws logs tail /ecs/flight-mock-api-dev/scraper --follow
```

### ECS Service Status

```bash
aws ecs describe-services \
  --cluster $(terraform output -raw ecs_cluster_name) \
  --services $(terraform output -raw mock_api_service_name)
```

### Check Scraped Data

```bash
aws s3 ls s3://$(terraform output -raw raw_bucket_name)/scraped/flights/ --recursive
```

## Cost Optimization

### Development/Testing
- `mock_api_desired_count = 1` (single instance)
- `single_nat_gateway = true`
- `mock_api_cpu = 256`, `mock_api_memory = 512`

### Production
- `mock_api_desired_count = 2` (high availability)
- `single_nat_gateway = false`
- `mock_api_cpu = 512`, `mock_api_memory = 1024`

### Estimated Monthly Costs (us-east-1)

**Development:**
- ECS Fargate (1 task): ~$15/month
- ALB: ~$16/month
- NAT Gateway (1): ~$32/month
- S3 storage (10GB): ~$0.25/month
- **Total: ~$63/month**

**Production:**
- ECS Fargate (2 tasks): ~$30/month
- ALB: ~$16/month
- NAT Gateway (2): ~$64/month
- S3 storage (100GB): ~$2.50/month
- **Total: ~$112/month**

## Troubleshooting

### Service Won't Start

```bash
# Check service events
aws ecs describe-services \
  --cluster $(terraform output -raw ecs_cluster_name) \
  --services $(terraform output -raw mock_api_service_name) \
  --query 'services[0].events[0:5]'

# Check task logs
aws logs tail $(terraform output -raw mock_api_log_group) --since 30m
```

### Can't Access API

```bash
# Check ALB target health
aws elbv2 describe-target-health \
  --target-group-arn $(aws elbv2 describe-target-groups \
    --names flight-mock-api-dev-mock-api-tg \
    --query 'TargetGroups[0].TargetGroupArn' --output text)

# Check security groups
aws ec2 describe-security-groups \
  --filters "Name=tag:Name,Values=flight-mock-api-dev-alb-sg"
```

### Scraper Not Running

```bash
# Check EventBridge rule
aws events describe-rule --name flight-mock-api-dev-scraper-schedule

# Check recent scraper executions
aws logs filter-log-events \
  --log-group-name $(terraform output -raw scraper_log_group) \
  --start-time $(date -u -d '1 hour ago' +%s)000
```

## Updating the Deployment

### Update Configuration

```bash
# Edit terraform.tfvars
terraform plan
terraform apply
```

### Update Docker Images

```bash
# Build new images
docker build -t $(terraform output -raw mock_api_ecr_repository_url):v1.1 .
docker push $(terraform output -raw mock_api_ecr_repository_url):v1.1

# Update task definition (edit terraform.tfvars)
mock_api_image_tag = "v1.1"

terraform apply
```

### Scale Service

```bash
# Edit terraform.tfvars
mock_api_desired_count = 3

terraform apply
```

## Destroying Resources

```bash
# WARNING: This will delete all resources including data!
terraform destroy

# To preserve S3 data, first:
# 1. Set raw_bucket_name to empty string in tfvars
# 2. Run: terraform apply
# 3. Then: terraform destroy
```

## Outputs

After deployment, Terraform provides:

- `alb_url`: API endpoint
- `mock_api_endpoint`: Realtime flights endpoint
- `mock_api_ecr_repository_url`: ECR URL for Mock API images
- `scraper_ecr_repository_url`: ECR URL for Scraper images
- `raw_bucket_name`: S3 bucket for data storage
- `ecs_cluster_name`: ECS cluster name
- `mock_api_log_group`: CloudWatch log group
- `next_steps`: Detailed deployment instructions

## Security

- ALB is public, ECS tasks run in private subnets
- Security groups restrict traffic to necessary ports
- ECR image scanning enabled
- CloudWatch logs for audit trail
- IAM roles follow least privilege principle
- S3 bucket versioning enabled

## Backup and Disaster Recovery

- S3 versioning enabled for data protection
- CloudWatch logs retained for 7 days
- Infrastructure as Code allows quick redeployment
- Consider enabling S3 cross-region replication for DR

## Support

For issues or questions:
1. Check CloudWatch logs
2. Review ECS service events
3. Verify security group rules
4. Check IAM role permissions
5. Review Terraform state for configuration issues
