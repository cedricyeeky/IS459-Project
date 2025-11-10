terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }

  # Optional: Configure backend for state management
  # backend "s3" {
  #   bucket         = "your-terraform-state-bucket"
  #   key            = "longterm/mock-api/terraform.tfstate"
  #   region         = "us-east-1"
  #   encrypt        = true
  #   dynamodb_table = "terraform-state-lock"
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      Purpose     = "Mock Flight API - Long Term"
    }
  }
}

# Data sources for existing resources
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
  source = "terraform-aws-modules/vpc/aws"
  count  = var.vpc_id == "" ? 1 : 0

  name = "${var.project_name}-${var.environment}-vpc"
  cidr = var.vpc_cidr

  azs             = var.availability_zones
  private_subnets = var.private_subnet_cidrs
  public_subnets  = var.public_subnet_cidrs

  enable_nat_gateway = true
  single_nat_gateway = var.single_nat_gateway
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

# S3 bucket removed - not needed for mock API only deployment

# ECR repository for mock API Docker image
resource "aws_ecr_repository" "mock_api" {
  name                 = "${var.project_name}-${var.environment}-mock-api"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name        = "${var.project_name}-${var.environment}-mock-api"
    Environment = var.environment
  }
}

# ECR Lifecycle Policy for mock API
resource "aws_ecr_lifecycle_policy" "mock_api" {
  repository = aws_ecr_repository.mock_api.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 10 images"
        selection = {
          tagStatus     = "any"
          countType     = "imageCountMoreThan"
          countNumber   = 10
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

# Scraper lifecycle policy removed - not needed for mock API only deployment

# Compute module (ECS, ALB) - Mock API only
module "compute" {
  source = "./compute"

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

  # Scraper configuration - disabled for mock API only deployment
  scraper_image               = ""
  scraper_cpu                 = 256
  scraper_memory              = 512
  scraper_schedule_expression = ""

  # S3 configuration - not needed for mock API only
  raw_bucket_name = ""

  tags = var.tags
}

# Data source for AWS account
data "aws_caller_identity" "current" {}
