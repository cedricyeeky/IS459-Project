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
  raw_bucket_name = module.s3.raw_bucket_name
  dlq_bucket_name = module.s3.dlq_bucket_name
  
  # Wikipedia URLs to scrape
  wikipedia_urls = var.wikipedia_urls
  
  tags = local.common_tags
}

# ============================================================================
# Glue Module - ETL Jobs and Data Catalog
# ============================================================================

module "glue" {
  source = "./modules/glue"

  resource_prefix = local.resource_prefix
  environment     = var.environment
  
  # IAM role
  glue_role_arn = module.iam.glue_role_arn
  
  # S3 buckets
  raw_bucket_name    = module.s3.raw_bucket_name
  silver_bucket_name = module.s3.silver_bucket_name
  gold_bucket_name   = module.s3.gold_bucket_name
  dlq_bucket_name    = module.s3.dlq_bucket_name
  
  # Glue job configuration
  glue_version           = var.glue_version
  cleaning_worker_count  = var.cleaning_worker_count
  feature_worker_count   = var.feature_worker_count
  cleaning_timeout       = var.cleaning_timeout
  feature_timeout        = var.feature_timeout
  
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
  alert_email = var.alert_email
  
  # EventBridge schedules
  scraping_schedule = var.scraping_schedule
  cleaning_schedule = var.cleaning_schedule
  crawler_schedule  = var.crawler_schedule
  
  # Lambda function ARN
  lambda_function_arn = module.lambda.lambda_function_arn
  
  # Glue job names
  cleaning_job_name = module.glue.cleaning_job_name
  
  # Glue workflow ARN
  glue_workflow_arn = module.glue.workflow_arn
  
  # Glue crawler names
  raw_crawler_name    = module.glue.raw_crawler_name
  silver_crawler_name = module.glue.silver_crawler_name
  gold_crawler_name   = module.glue.gold_crawler_name
  
  tags = local.common_tags
}

