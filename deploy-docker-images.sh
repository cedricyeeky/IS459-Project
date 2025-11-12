#!/bin/bash

# ============================================================================
# Docker Image Build & Deploy Script - DEV
# ============================================================================
# This script builds and pushes Docker images for:
# 1. Mock API (ECS)
# 2. Scraper (ECS)
# 3. Lambda Scraped Processor
#
# Prerequisites:
# - Docker installed and running
# - AWS CLI configured
# - Terraform applied (to create ECR repositories)
# ============================================================================

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$SCRIPT_DIR/terraform"
AWS_REGION="us-east-1"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Docker Image Build & Deploy Script${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# ============================================================================
# Function: Check Prerequisites
# ============================================================================
check_prerequisites() {
    echo -e "${YELLOW}Checking prerequisites...${NC}"

    # Check Docker
    if ! command -v docker &> /dev/null; then
        echo -e "${RED}ERROR: Docker is not installed${NC}"
        exit 1
    fi

    # Check if Docker daemon is running
    if ! docker info &> /dev/null; then
        echo -e "${RED}ERROR: Docker daemon is not running${NC}"
        exit 1
    fi

    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        echo -e "${RED}ERROR: AWS CLI is not installed${NC}"
        exit 1
    fi

    # Check Terraform
    if ! command -v terraform &> /dev/null; then
        echo -e "${RED}ERROR: Terraform is not installed${NC}"
        exit 1
    fi

    # Check if Terraform has been initialized
    if [ ! -d "$TERRAFORM_DIR/.terraform" ]; then
        echo -e "${RED}ERROR: Terraform not initialized. Run 'cd terraform && terraform init' first${NC}"
        exit 1
    fi

    echo -e "${GREEN}✓ All prerequisites met${NC}"
    echo ""
}

# ============================================================================
# Function: Get ECR URLs from Terraform
# ============================================================================
get_ecr_urls() {
    echo -e "${YELLOW}Getting ECR repository URLs from Terraform...${NC}"

    cd "$TERRAFORM_DIR"

    # Check if terraform state exists
    if [ ! -f "terraform.tfstate" ]; then
        echo -e "${RED}ERROR: Terraform state not found. Run 'terraform apply' first${NC}"
        exit 1
    fi

    MOCK_API_ECR=$(terraform output -raw mock_api_ecr_repository_url 2>/dev/null || echo "")
    SCRAPER_ECR=$(terraform output -raw scraper_ecr_repository_url 2>/dev/null || echo "")

    if [ -z "$MOCK_API_ECR" ] || [ -z "$SCRAPER_ECR" ]; then
        echo -e "${RED}ERROR: Could not get ECR URLs from Terraform. Ensure 'terraform apply' has been run.${NC}"
        exit 1
    fi

    echo -e "${GREEN}✓ Mock API ECR: $MOCK_API_ECR${NC}"
    echo -e "${GREEN}✓ Scraper ECR: $SCRAPER_ECR${NC}"
    echo ""

    cd "$SCRIPT_DIR"
}

# ============================================================================
# Function: Login to ECR
# ============================================================================
ecr_login() {
    echo -e "${YELLOW}Logging in to Amazon ECR...${NC}"

    aws ecr get-login-password --region $AWS_REGION | \
        docker login --username AWS --password-stdin \
        "$(echo $MOCK_API_ECR | cut -d'/' -f1)" || {
        echo -e "${RED}ERROR: Failed to login to ECR${NC}"
        exit 1
    }

    echo -e "${GREEN}✓ Successfully logged in to ECR${NC}"
    echo ""
}

# ============================================================================
# Function: Build and Push Mock API
# ============================================================================
build_push_mock_api() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}  Building Mock API Docker Image${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""

    MOCK_API_DIR="$TERRAFORM_DIR/modules/mock_api_ecs/src"

    if [ ! -f "$MOCK_API_DIR/Dockerfile" ]; then
        echo -e "${RED}ERROR: Mock API Dockerfile not found at $MOCK_API_DIR${NC}"
        exit 1
    fi

    echo -e "${YELLOW}Building image...${NC}"
    cd "$MOCK_API_DIR"

    docker build --platform linux/amd64 -t mock-api:latest . || {
        echo -e "${RED}ERROR: Failed to build Mock API image${NC}"
        exit 1
    }

    echo -e "${GREEN}✓ Mock API image built successfully${NC}"
    echo ""

    echo -e "${YELLOW}Tagging and pushing to ECR...${NC}"
    docker tag mock-api:latest "$MOCK_API_ECR:latest"
    docker push "$MOCK_API_ECR:latest" || {
        echo -e "${RED}ERROR: Failed to push Mock API image${NC}"
        exit 1
    }

    echo -e "${GREEN}✓ Mock API image pushed to ECR${NC}"
    echo ""

    cd "$SCRIPT_DIR"
}

# ============================================================================
# Function: Build and Push Scraper
# ============================================================================
build_push_scraper() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}  Building Scraper Docker Image${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""

    SCRAPER_DIR="$TERRAFORM_DIR/modules/scraper_ecs/src"

    if [ ! -f "$SCRAPER_DIR/Dockerfile" ]; then
        echo -e "${RED}ERROR: Scraper Dockerfile not found at $SCRAPER_DIR${NC}"
        exit 1
    fi

    echo -e "${YELLOW}Building image...${NC}"
    cd "$SCRAPER_DIR"

    docker build --platform linux/amd64 -t scraper:latest . || {
        echo -e "${RED}ERROR: Failed to build Scraper image${NC}"
        exit 1
    }

    echo -e "${GREEN}✓ Scraper image built successfully${NC}"
    echo ""

    echo -e "${YELLOW}Tagging and pushing to ECR...${NC}"
    docker tag scraper:latest "$SCRAPER_ECR:latest"
    docker push "$SCRAPER_ECR:latest" || {
        echo -e "${RED}ERROR: Failed to push Scraper image${NC}"
        exit 1
    }

    echo -e "${GREEN}✓ Scraper image pushed to ECR${NC}"
    echo ""

    cd "$SCRIPT_DIR"
}

# ============================================================================
# Function: Build and Push Lambda Scraped Processor
# ============================================================================
build_push_lambda() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}  Building Lambda Scraped Processor${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""

    LAMBDA_DIR="$TERRAFORM_DIR/modules/lambda_scraped_processed/src"
    LAMBDA_ECR="820242928352.dkr.ecr.us-east-1.amazonaws.com/flight-delays-scraped-processor"

    if [ ! -f "$LAMBDA_DIR/Dockerfile" ]; then
        echo -e "${RED}ERROR: Lambda Dockerfile not found at $LAMBDA_DIR${NC}"
        return 1
    fi

    echo -e "${YELLOW}Building image...${NC}"
    cd "$LAMBDA_DIR"

    docker build --platform linux/amd64 -t flight-delays-scraped-processor:latest . || {
        echo -e "${RED}ERROR: Failed to build Lambda image${NC}"
        return 1
    }

    echo -e "${GREEN}✓ Lambda image built successfully${NC}"
    echo ""

    echo -e "${YELLOW}Tagging and pushing to ECR...${NC}"
    docker tag flight-delays-scraped-processor:latest "$LAMBDA_ECR:latest"
    docker push "$LAMBDA_ECR:latest" || {
        echo -e "${RED}ERROR: Failed to push Lambda image${NC}"
        return 1
    }

    echo -e "${GREEN}✓ Lambda image pushed to ECR${NC}"
    echo ""

    # Update Lambda function
    echo -e "${YELLOW}Updating Lambda function...${NC}"
    aws lambda update-function-code \
        --function-name flight-delays-dev-scraped-processor \
        --image-uri "$LAMBDA_ECR:latest" \
        --region $AWS_REGION &> /dev/null || {
        echo -e "${YELLOW}Warning: Could not update Lambda function (may not exist yet)${NC}"
    }

    echo -e "${GREEN}✓ Lambda function updated${NC}"
    echo ""

    cd "$SCRIPT_DIR"
}

# ============================================================================
# Function: Restart ECS Services
# ============================================================================
restart_ecs_services() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}  Restarting ECS Services${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""

    cd "$TERRAFORM_DIR"

    # Get cluster and service names from Terraform
    CLUSTER_NAME=$(terraform output -raw ecs_cluster_name 2>/dev/null || echo "")
    MOCK_API_SERVICE=$(terraform output -raw mock_api_service_name 2>/dev/null || echo "")

    if [ -z "$CLUSTER_NAME" ] || [ -z "$MOCK_API_SERVICE" ]; then
        echo -e "${YELLOW}Warning: Could not get ECS service names from Terraform${NC}"
        echo -e "${YELLOW}ECS services may not be created yet. Run 'terraform apply' first.${NC}"
        cd "$SCRIPT_DIR"
        return 0
    fi

    echo -e "${YELLOW}Restarting Mock API service...${NC}"
    aws ecs update-service \
        --cluster "$CLUSTER_NAME" \
        --service "$MOCK_API_SERVICE" \
        --force-new-deployment \
        --region $AWS_REGION &> /dev/null && \
        echo -e "${GREEN}✓ Mock API service restart triggered${NC}" || \
        echo -e "${YELLOW}Warning: Could not restart Mock API service${NC}"

    echo ""
    echo -e "${YELLOW}Note: Scraper runs on schedule via EventBridge (no restart needed)${NC}"
    echo ""

    cd "$SCRIPT_DIR"
}

# ============================================================================
# Function: Display Summary
# ============================================================================
display_summary() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}  Deployment Complete!${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    echo -e "${GREEN}✓ Mock API image built and pushed${NC}"
    echo -e "${GREEN}✓ Scraper image built and pushed${NC}"

    if [ "$BUILD_LAMBDA" = true ]; then
        echo -e "${GREEN}✓ Lambda image built and pushed${NC}"
    fi

    echo ""
    echo -e "${YELLOW}Next steps:${NC}"
    echo -e "  1. If this is first deployment: ${BLUE}cd terraform && terraform apply${NC}"
    echo -e "  2. Check ECS services: ${BLUE}aws ecs describe-services --cluster <cluster-name> --services <service-name>${NC}"
    echo -e "  3. View Mock API endpoint: ${BLUE}cd terraform && terraform output alb_url${NC}"
    echo -e "  4. Monitor logs: ${BLUE}aws logs tail /ecs/<log-group-name> --follow${NC}"
    echo ""
}

# ============================================================================
# Main Script
# ============================================================================

# Parse command line arguments
BUILD_LAMBDA=true
SKIP_RESTART=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-lambda)
            BUILD_LAMBDA=false
            shift
            ;;
        --skip-restart)
            SKIP_RESTART=true
            shift
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --skip-lambda    Skip building and pushing Lambda scraped processor image"
            echo "  --skip-restart   Skip restarting ECS services after push"
            echo "  --help          Show this help message"
            echo ""
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            echo "Run with --help for usage information"
            exit 1
            ;;
    esac
done

# Execute deployment steps
check_prerequisites
get_ecr_urls
ecr_login
build_push_mock_api
build_push_scraper

if [ "$BUILD_LAMBDA" = true ]; then
    build_push_lambda
fi

if [ "$SKIP_RESTART" = false ]; then
    restart_ecs_services
fi

display_summary

echo -e "${GREEN}All done! 🚀${NC}"
