# ============================================================================
# Lambda Module - Input Variables
# ============================================================================

variable "resource_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "lambda_role_arn" {
  description = "ARN of the Lambda execution role"
  type        = string
}

variable "lambda_memory_size" {
  description = "Memory allocation for Lambda function in MB"
  type        = number
}

variable "lambda_timeout" {
  description = "Lambda function timeout in seconds"
  type        = number
}

variable "raw_bucket_name" {
  description = "Name of the raw data S3 bucket"
  type        = string
}

variable "dlq_bucket_name" {
  description = "Name of the DLQ S3 bucket"
  type        = string
}

variable "wikipedia_urls" {
  description = "List of Wikipedia URLs to scrape"
  type        = list(string)
}

variable "tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}

