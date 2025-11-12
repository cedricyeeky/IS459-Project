variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "vpc_id" {
  description = "VPC ID where ECS resources will be deployed"
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for ECS tasks"
  type        = list(string)
}

variable "public_subnet_ids" {
  description = "List of public subnet IDs for ALB"
  type        = list(string)
}

variable "mock_api_image" {
  description = "Docker image for mock flight API"
  type        = string
  default     = "mock-flight-api:latest"
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
  default     = 1
}

variable "scraper_image" {
  description = "Docker image for scraper task"
  type        = string
  default     = "flight-scraper:latest"
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
  description = "EventBridge schedule expression for scraper (cron or rate)"
  type        = string
  default     = "rate(15 minutes)"
}

variable "raw_bucket_name" {
  description = "S3 bucket name for raw data storage"
  type        = string
}

variable "tags" {
  description = "Additional tags for resources"
  type        = map(string)
  default     = {}
}
