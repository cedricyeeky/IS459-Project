variable "resource_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "sns_topic_arn" {
  description = "ARN of the SNS topic to publish notifications"
  type        = string
}

variable "dlq_bucket_name" {
  description = "Name of the DLQ S3 bucket"
  type        = string
}

variable "dlq_bucket_arn" {
  description = "ARN of the DLQ S3 bucket"
  type        = string
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
