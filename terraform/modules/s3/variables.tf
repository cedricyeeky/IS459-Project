# ============================================================================
# S3 Module - Input Variables
# ============================================================================

variable "resource_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "raw_lifecycle_days" {
  description = "Days before transitioning raw bucket objects to IA"
  type        = number
}

variable "silver_lifecycle_days" {
  description = "Days before transitioning silver bucket objects to IA"
  type        = number
}

variable "gold_lifecycle_days" {
  description = "Days before transitioning gold bucket objects to IA"
  type        = number
}

variable "dlq_expiration_days" {
  description = "Days before expiring DLQ bucket objects"
  type        = number
}

variable "dlq_sns_topic_arn" {
  description = "ARN of SNS topic for DLQ notifications"
  type        = string
}

variable "tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}

