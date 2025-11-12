# ============================================================================
# Glue Module - Input Variables
# ============================================================================

variable "resource_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "glue_role_arn" {
  description = "ARN of the Glue service role"
  type        = string
}

variable "raw_bucket_name" {
  description = "Name of the raw data S3 bucket"
  type        = string
}

variable "silver_bucket_name" {
  description = "Name of the silver data S3 bucket"
  type        = string
}

variable "gold_bucket_name" {
  description = "Name of the gold data S3 bucket"
  type        = string
}

variable "dlq_bucket_name" {
  description = "Name of the DLQ S3 bucket"
  type        = string
}

variable "glue_version" {
  description = "AWS Glue version"
  type        = string
}

variable "cleaning_worker_count" {
  description = "Number of workers for data cleaning job"
  type        = number
}

variable "feature_worker_count" {
  description = "Number of workers for feature engineering job"
  type        = number
}

variable "cleaning_timeout" {
  description = "Timeout for data cleaning job in minutes"
  type        = number
}

variable "feature_timeout" {
  description = "Timeout for feature engineering job in minutes"
  type        = number
}

variable "tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "aws_account_id" {
  description = "AWS account ID"
  type        = string
}

# NOTE: scraped_processor_lambda_arn variable removed - now using S3 notifications instead of EventBridge

