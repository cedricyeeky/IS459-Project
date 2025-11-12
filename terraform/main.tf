# ============================================================================
# Flight Delays Data Pipeline - Root Configuration
# ============================================================================
# This is the main entry point for the Terraform configuration.
# It orchestrates all modules and establishes resource dependencies.

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Uncomment and configure for remote state management
  # backend "s3" {
  #   bucket         = "your-terraform-state-bucket"
  #   key            = "flight-delays-pipeline/terraform.tfstate"
  #   region         = "us-east-1"
  #   encrypt        = true
  #   dynamodb_table = "terraform-state-lock"
  # }
}

# ============================================================================
# Provider Configuration
# ============================================================================

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "flight-delays-pipeline"
      Environment = var.environment
      ManagedBy   = "terraform"
      CostCenter  = var.cost_center
    }
  }
}

# ============================================================================
# Local Variables
# ============================================================================

# Get current AWS account ID
data "aws_caller_identity" "current" {}

locals {
  # Construct resource name prefix with environment
  resource_prefix = "${var.resource_prefix}-${var.environment}"

  # Common tags to be merged with default tags
  common_tags = {
    Project     = "flight-delays-pipeline"
    Environment = var.environment
    ManagedBy   = "terraform"
    CostCenter  = var.cost_center
  }
}

# ============================================================================
# IAM Module - Must be created first
# ============================================================================

module "iam" {
  source = "./modules/iam"

  resource_prefix = local.resource_prefix
  environment     = var.environment

  # S3 bucket ARNs will be passed after creation
  raw_bucket_arn    = module.s3.raw_bucket_arn
  silver_bucket_arn = module.s3.silver_bucket_arn
  gold_bucket_arn   = module.s3.gold_bucket_arn
  dlq_bucket_arn    = module.s3.dlq_bucket_arn

  # Glue script bucket for storing PySpark scripts
  glue_script_bucket_arn = module.s3.raw_bucket_arn

  tags = local.common_tags
}

# ============================================================================
# S3 Module - Storage Layer
# ============================================================================

module "s3" {
  source = "./modules/s3"

  resource_prefix = local.resource_prefix
  environment     = var.environment

  # Lifecycle policies
  raw_lifecycle_days    = var.raw_lifecycle_days
  silver_lifecycle_days = var.silver_lifecycle_days
  gold_lifecycle_days   = var.gold_lifecycle_days
  dlq_expiration_days   = var.dlq_expiration_days

  # SNS topic ARN for DLQ notifications (created in notifications module)
  dlq_sns_topic_arn = module.notifications.dlq_sns_topic_arn

  tags = local.common_tags
}

# ============================================================================
# Lambda Module - Web Scraping
# ============================================================================

module "lambda" {
  source = "./modules/lambda"

  resource_prefix = local.resource_prefix
  environment     = var.environment

  # Lambda configuration
  lambda_memory_size = var.lambda_memory_size
  lambda_timeout     = var.lambda_timeout

  # IAM role
  lambda_role_arn = module.iam.lambda_role_arn

  # S3 buckets
  raw_bucket_name    = module.s3.raw_bucket_name
  silver_bucket_name = module.s3.silver_bucket_name
  dlq_bucket_name    = module.s3.dlq_bucket_name

  # EventBridge rule ARN for scraped processor (will be created by Glue module)
  eventbridge_rule_arn = module.glue.scraped_data_trigger_rule_arn

  tags = local.common_tags
}

# ============================================================================
# Glue Module - ETL Jobs and Data Catalog
# ============================================================================

module "glue" {
  source = "./modules/glue"

  resource_prefix = local.resource_prefix
  environment     = var.environment

  # IAM roles
  glue_role_arn = module.iam.glue_role_arn

  # S3 buckets
  raw_bucket_name    = module.s3.raw_bucket_name
  silver_bucket_name = module.s3.silver_bucket_name
  gold_bucket_name   = module.s3.gold_bucket_name
  dlq_bucket_name    = module.s3.dlq_bucket_name

  # AWS account information
  aws_region     = var.aws_region
  aws_account_id = data.aws_caller_identity.current.account_id

  # Lambda function ARN for scraped data processing
  scraped_processor_lambda_arn = module.lambda.scraped_processor_function_arn

  # Glue job configuration
  glue_version          = var.glue_version
  cleaning_worker_count = var.cleaning_worker_count
  feature_worker_count  = var.feature_worker_count
  cleaning_timeout      = var.cleaning_timeout
  feature_timeout       = var.feature_timeout

  tags = local.common_tags
}

# ============================================================================
# Notifications Module - SNS and EventBridge
# ============================================================================

module "notifications" {
  source = "./modules/notifications"

  resource_prefix = local.resource_prefix
  environment     = var.environment

  # SNS configuration
  alert_email      = var.alert_email
  aws_account_id   = data.aws_caller_identity.current.account_id
  dlq_bucket_name  = module.s3.dlq_bucket_name

  # EventBridge schedules
  cleaning_schedule = var.cleaning_schedule
  crawler_schedule  = var.crawler_schedule

  # Glue workflow ARN
  glue_workflow_arn = module.glue.workflow_arn

  # Glue crawler names
  raw_crawler_name    = module.glue.raw_crawler_name
  silver_crawler_name = module.glue.silver_crawler_name
  gold_crawler_name   = module.glue.gold_crawler_name

  tags = local.common_tags
}

# ============================================================================
# Lambda DLQ Notifier - S3 → Lambda → SNS
# ============================================================================

module "lambda_dlq_notifier" {
  source = "./modules/lambda_dlq_notifier"

  resource_prefix  = local.resource_prefix
  sns_topic_arn    = module.notifications.dlq_sns_topic_arn
  dlq_bucket_name  = module.s3.dlq_bucket_name
  dlq_bucket_arn   = module.s3.dlq_bucket_arn

  tags = local.common_tags
}

# ============================================================================
# Athena Module - Analytics Query Layer (Phase 1)
# ============================================================================

module "athena" {
  source = "./modules/athena"

  resource_prefix = local.resource_prefix
  database_name   = module.glue.database_name
  raw_bucket_name = module.s3.raw_bucket_name

  tags = local.common_tags
}

# ============================================================================
# Mock API & Scraper Infrastructure (ECS-based)
# ============================================================================
# This section creates the long-running Mock API service and scheduled scraper
# Migrated from terraform/longterm/

# Data sources for existing VPC resources (if using existing VPC)
data "aws_vpc" "main" {
  count = var.vpc_id != "" ? 1 : 0
  id    = var.vpc_id
}

data "aws_subnets" "private" {
  count = var.vpc_id != "" ? 1 : 0

  filter {
    name   = "vpc-id"
    values = [var.vpc_id]
  }

  tags = {
    Tier = "Private"
  }
}

data "aws_subnets" "public" {
  count = var.vpc_id != "" ? 1 : 0

  filter {
    name   = "vpc-id"
    values = [var.vpc_id]
  }

  tags = {
    Tier = "Public"
  }
}

# Create VPC if not provided
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"
  count   = var.vpc_id == "" ? 1 : 0

  name = "${var.project_name}-${var.environment}-vpc"
  cidr = var.vpc_cidr

  azs             = var.availability_zones
  private_subnets = var.private_subnet_cidrs
  public_subnets  = var.public_subnet_cidrs

  enable_nat_gateway   = true
  single_nat_gateway   = var.single_nat_gateway
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.project_name}-${var.environment}-vpc"
  }

  public_subnet_tags = {
    Tier = "Public"
  }

  private_subnet_tags = {
    Tier = "Private"
  }
}

# ECR repository for Mock API Docker image
resource "aws_ecr_repository" "mock_api" {
  name                 = "${var.project_name}-${var.environment}-mock-api"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${var.project_name}-${var.environment}-mock-api"
    }
  )
}

# ECR Lifecycle Policy for Mock API
resource "aws_ecr_lifecycle_policy" "mock_api" {
  repository = aws_ecr_repository.mock_api.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 10 images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

# ECR repository for Scraper Docker image
resource "aws_ecr_repository" "scraper" {
  name                 = "${var.project_name}-${var.environment}-scraper"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${var.project_name}-${var.environment}-scraper"
    }
  )
}

# ECR Lifecycle Policy for Scraper
resource "aws_ecr_lifecycle_policy" "scraper" {
  repository = aws_ecr_repository.scraper.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 10 images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

# ============================================================================
# Mock API ECS Module
# ============================================================================
# Creates ECS cluster, service, ALB for Mock Flight API

module "mock_api_ecs" {
  source = "./modules/mock_api_ecs"

  project_name       = var.project_name
  environment        = var.environment
  vpc_id             = var.vpc_id != "" ? var.vpc_id : module.vpc[0].vpc_id
  private_subnet_ids = var.vpc_id != "" ? data.aws_subnets.private[0].ids : module.vpc[0].private_subnets
  public_subnet_ids  = var.vpc_id != "" ? data.aws_subnets.public[0].ids : module.vpc[0].public_subnets

  # Mock API configuration
  mock_api_image         = "${aws_ecr_repository.mock_api.repository_url}:${var.mock_api_image_tag}"
  mock_api_port          = var.mock_api_port
  mock_api_cpu           = var.mock_api_cpu
  mock_api_memory        = var.mock_api_memory
  mock_api_desired_count = var.mock_api_desired_count

  # S3 configuration - using shared raw bucket
  raw_bucket_name = module.s3.raw_bucket_name

  tags = local.common_tags
}

# ============================================================================
# Scraper ECS Module
# ============================================================================
# Creates EventBridge scheduled ECS task for scraping flight/weather data

module "scraper_ecs" {
  source = "./modules/scraper_ecs"

  project_name       = var.project_name
  environment        = var.environment
  aws_region         = var.aws_region
  ecs_cluster_arn    = module.mock_api_ecs.ecs_cluster_arn
  private_subnet_ids = var.vpc_id != "" ? data.aws_subnets.private[0].ids : module.vpc[0].private_subnets

  scraper_security_group_id   = module.mock_api_ecs.scraper_security_group_id
  scraper_image               = "${aws_ecr_repository.scraper.repository_url}:${var.scraper_image_tag}"
  scraper_cpu                 = var.scraper_cpu
  scraper_memory              = var.scraper_memory
  scraper_schedule_expression = var.scraper_schedule_expression

  # API endpoint (ALB DNS name)
  api_endpoint = "http://${module.mock_api_ecs.alb_dns_name}"

  # S3 bucket for raw data
  raw_bucket_name = module.s3.raw_bucket_name
  raw_bucket_arn  = module.s3.raw_bucket_arn

  tags = local.common_tags
}

