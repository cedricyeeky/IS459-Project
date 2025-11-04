# ============================================================================
# Notifications Module - Input Variables
# ============================================================================

variable "resource_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "alert_email" {
  description = "Email address for DLQ alerts"
  type        = string
}

variable "scraping_schedule" {
  description = "Cron expression for Lambda scraper schedule"
  type        = string
}

variable "cleaning_schedule" {
  description = "Cron expression for Glue cleaning job schedule"
  type        = string
}

variable "crawler_schedule" {
  description = "Cron expression for Glue crawlers schedule"
  type        = string
}

variable "lambda_function_arn" {
  description = "ARN of the Lambda function"
  type        = string
}

variable "glue_workflow_arn" {
  description = "ARN of the Glue workflow"
  type        = string
}

variable "raw_crawler_name" {
  description = "Name of the raw data crawler"
  type        = string
}

variable "silver_crawler_name" {
  description = "Name of the silver data crawler"
  type        = string
}

variable "gold_crawler_name" {
  description = "Name of the gold data crawler"
  type        = string
}

variable "tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}

