# ============================================================================
# IAM Module - Input Variables
# ============================================================================

variable "resource_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "raw_bucket_arn" {
  description = "ARN of the raw data S3 bucket"
  type        = string
}

variable "silver_bucket_arn" {
  description = "ARN of the silver data S3 bucket"
  type        = string
}

variable "gold_bucket_arn" {
  description = "ARN of the gold data S3 bucket"
  type        = string
}

variable "dlq_bucket_arn" {
  description = "ARN of the DLQ S3 bucket"
  type        = string
}

variable "glue_script_bucket_arn" {
  description = "ARN of the bucket storing Glue scripts"
  type        = string
}

variable "tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}

