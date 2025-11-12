#!/bin/bash
# Redeploy scraper with updated S3 path structure
# Run this from the terraform/modules/scraper_ecs/src/ directory

set -e

echo "=========================================="
echo "Redeploying Scraper with Flat S3 Structure"
echo "=========================================="

# Check if we're in the scraper src directory
if [ ! -f "app.py" ]; then
    echo "Error: Must run from terraform/modules/scraper_ecs/src/ directory"
    exit 1
fi

# Get AWS account ID and region
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
AWS_REGION=${AWS_REGION:-us-east-1}
ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
REPOSITORY_NAME="flight-mock-api-prod-scraper"
IMAGE_TAG="latest"

echo ""
echo "Configuration:"
echo "  AWS Account: $AWS_ACCOUNT_ID"
echo "  AWS Region: $AWS_REGION"
echo "  ECR Registry: $ECR_REGISTRY"
echo "  Repository: $REPOSITORY_NAME"
echo "  Image Tag: $IMAGE_TAG"
echo ""

# Step 1: Login to ECR
echo "Step 1: Logging into ECR..."
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_REGISTRY
echo "✓ Logged into ECR"
echo ""

# Step 2: Build Docker image
echo "Step 2: Building Docker image..."
docker build -t $REPOSITORY_NAME:$IMAGE_TAG .
echo "✓ Docker image built"
echo ""

# Step 3: Tag image for ECR
echo "Step 3: Tagging image for ECR..."
docker tag $REPOSITORY_NAME:$IMAGE_TAG $ECR_REGISTRY/$REPOSITORY_NAME:$IMAGE_TAG
echo "✓ Image tagged"
echo ""

# Step 4: Push to ECR
echo "Step 4: Pushing image to ECR..."
docker push $ECR_REGISTRY/$REPOSITORY_NAME:$IMAGE_TAG
echo "✓ Image pushed to ECR"
echo ""

# Step 5: Force new ECS task deployment
echo "Step 5: Forcing new ECS task deployment..."
cd ../../../../longterm

# Get ECS cluster and service names from Terraform
ECS_CLUSTER=$(terraform output -raw ecs_cluster_name 2>/dev/null || echo "flight-mock-api-prod-cluster")

echo "  ECS Cluster: $ECS_CLUSTER"
echo ""

# The scraper runs as a scheduled ECS task (not a service), so we just need to wait for next run
echo "✓ Image updated in ECR"
echo ""
echo "=========================================="
echo "Deployment Complete!"
echo "=========================================="
echo ""
echo "Next Steps:"
echo "1. The scraper will use the new image on the next scheduled run (every 15 minutes)"
echo "2. Or trigger manually:"
echo "   aws ecs run-task \\"
echo "     --cluster $ECS_CLUSTER \\"
echo "     --launch-type FARGATE \\"
echo "     --task-definition flight-mock-api-prod-scraper \\"
echo "     --network-configuration 'awsvpcConfiguration={subnets=[subnet-xxx],securityGroups=[sg-xxx]}'"
echo ""
echo "3. Check logs in CloudWatch:"
echo "   aws logs tail /ecs/flight-mock-api-prod/scraper --follow"
echo ""
echo "New S3 structure: s3://flight-mock-api-prod-raw/scraped/{weather|flights}/filename.json"
echo ""
