# ============================================
# General Configuration
# ============================================
variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "flight-mock-api"
}

variable "environment" {
  description = "Environment (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "tags" {
  description = "Additional tags for resources"
  type        = map(string)
  default     = {}
}

# ============================================
# Network Configuration
# ============================================
variable "vpc_id" {
  description = "Existing VPC ID (leave empty to create new VPC)"
  type        = string
  default     = ""
}

variable "vpc_cidr" {
  description = "CIDR block for VPC (only used if creating new VPC)"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "Availability zones for VPC (only used if creating new VPC)"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets (only used if creating new VPC)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets (only used if creating new VPC)"
  type        = list(string)
  default     = ["10.0.101.0/24", "10.0.102.0/24"]
}

variable "single_nat_gateway" {
  description = "Use single NAT gateway for cost savings (only used if creating new VPC)"
  type        = bool
  default     = true
}

# ============================================
# S3 Configuration
# ============================================
variable "raw_bucket_name" {
  description = "Existing S3 bucket name for raw data (leave empty to create new bucket)"
  type        = string
  default     = ""
}

variable "raw_data_retention_days" {
  description = "Number of days to retain raw data before expiration"
  type        = number
  default     = 90
}

# ============================================
# Mock API Configuration
# ============================================
variable "mock_api_image_tag" {
  description = "Docker image tag for mock API"
  type        = string
  default     = "latest"
}

variable "mock_api_port" {
  description = "Port for mock API container"
  type        = number
  default     = 5200
}

variable "mock_api_cpu" {
  description = "CPU units for mock API task (1024 = 1 vCPU)"
  type        = number
  default     = 512
}

variable "mock_api_memory" {
  description = "Memory for mock API task in MB"
  type        = number
  default     = 1024
}

variable "mock_api_desired_count" {
  description = "Desired number of mock API tasks"
  type        = number
  default     = 2
}

# ============================================
# Scraper Configuration
# ============================================
variable "scraper_image_tag" {
  description = "Docker image tag for scraper"
  type        = string
  default     = "latest"
}

variable "scraper_cpu" {
  description = "CPU units for scraper task"
  type        = number
  default     = 256
}

variable "scraper_memory" {
  description = "Memory for scraper task in MB"
  type        = number
  default     = 512
}

variable "scraper_schedule_expression" {
  description = "EventBridge schedule expression for scraper"
  type        = string
  default     = "rate(15 minutes)"
  
  validation {
    condition     = can(regex("^(rate|cron)\\(.*\\)$", var.scraper_schedule_expression))
    error_message = "Schedule expression must be in EventBridge format: rate(X minutes|hours|days) or cron(...)"
  }
}
