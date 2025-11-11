# ============================================================================
# Scraper Module - Input Variables
# ============================================================================

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "ecs_cluster_arn" {
  description = "ARN of the ECS cluster to run scraper tasks"
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for ECS tasks"
  type        = list(string)
}

variable "scraper_security_group_id" {
  description = "Security group ID for scraper ECS tasks"
  type        = string
}

variable "scraper_image" {
  description = "Docker image for scraper (ECR repository URL with tag)"
  type        = string
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
  description = "EventBridge schedule expression (e.g., 'rate(15 minutes)')"
  type        = string
  default     = "rate(15 minutes)"
}

variable "api_endpoint" {
  description = "Mock API endpoint URL (ALB DNS name)"
  type        = string
}

variable "raw_bucket_name" {
  description = "Name of the S3 raw data bucket"
  type        = string
}

variable "raw_bucket_arn" {
  description = "ARN of the S3 raw data bucket"
  type        = string
}

variable "tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}
