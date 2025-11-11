# ============================================================================
# Flight Delays Data Pipeline - Input Variables
# ============================================================================

# ----------------------------------------------------------------------------
# General Configuration
# ----------------------------------------------------------------------------

variable "aws_region" {
  description = "AWS region where resources will be deployed"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod"
  }
}

variable "resource_prefix" {
  description = "Prefix for all resource names"
  type        = string
  default     = "flight-delays"
}

variable "cost_center" {
  description = "Cost center tag for resource billing"
  type        = string
  default     = "data-engineering"
}

# ----------------------------------------------------------------------------
# S3 Lifecycle Configuration
# ----------------------------------------------------------------------------

variable "raw_lifecycle_days" {
  description = "Days before transitioning raw bucket objects to Infrequent Access"
  type        = number
  default     = 90
}

variable "silver_lifecycle_days" {
  description = "Days before transitioning silver bucket objects to Infrequent Access"
  type        = number
  default     = 60
}

variable "gold_lifecycle_days" {
  description = "Days before transitioning gold bucket objects to Infrequent Access"
  type        = number
  default     = 30
}

variable "dlq_expiration_days" {
  description = "Days before expiring DLQ bucket objects"
  type        = number
  default     = 30
}

# ----------------------------------------------------------------------------
# Lambda Configuration
# ----------------------------------------------------------------------------

variable "lambda_memory_size" {
  description = "Memory allocation for Lambda function in MB"
  type        = number
  default     = 512

  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory must be between 128 MB and 10240 MB"
  }
}

variable "lambda_timeout" {
  description = "Lambda function timeout in seconds"
  type        = number
  default     = 300

  validation {
    condition     = var.lambda_timeout >= 1 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 1 and 900 seconds"
  }
}

variable "wikipedia_urls" {
  description = "List of Wikipedia URLs to scrape for supplemental data"
  type        = list(string)
  default = [
    "https://en.wikipedia.org/wiki/Federal_holidays_in_the_United_States",
    "https://en.wikipedia.org/wiki/List_of_accidents_and_incidents_involving_commercial_aircraft"
  ]
}

# ----------------------------------------------------------------------------
# Glue Configuration
# ----------------------------------------------------------------------------

variable "glue_version" {
  description = "AWS Glue version"
  type        = string
  default     = "4.0"
}

variable "cleaning_worker_count" {
  description = "Number of workers for data cleaning Glue job"
  type        = number
  default     = 2
}

variable "feature_worker_count" {
  description = "Number of workers for feature engineering Glue job"
  type        = number
  default     = 2
}

variable "cleaning_timeout" {
  description = "Timeout for data cleaning job in minutes"
  type        = number
  default     = 30
}

variable "feature_timeout" {
  description = "Timeout for feature engineering job in minutes"
  type        = number
  default     = 45
}

# ----------------------------------------------------------------------------
# Notification Configuration
# ----------------------------------------------------------------------------

variable "alert_email" {
  description = "Email address for DLQ alerts (replace with your email)"
  type        = string
  default     = "your-email@example.com"
}

# ----------------------------------------------------------------------------
# Schedule Configuration (Cron Expressions)
# ----------------------------------------------------------------------------

variable "scraping_schedule" {
  description = "Cron expression for Lambda scraper schedule (weekly Saturdays at 11 PM UTC)"
  type        = string
  default     = "cron(0 23 ? * SAT *)"
}

variable "cleaning_schedule" {
  description = "Cron expression for Glue cleaning job schedule (weekly Sundays at 1 AM UTC)"
  type        = string
  default     = "cron(0 1 ? * SUN *)"
}

variable "crawler_schedule" {
  description = "Cron expression for Glue crawlers schedule (weekly Sundays at 2 AM UTC)"
  type        = string
  default     = "cron(0 2 ? * SUN *)"
}

# ----------------------------------------------------------------------------
# QuickSight Configuration
# ----------------------------------------------------------------------------

variable "enable_quicksight" {
  description = "Toggle to enable Amazon QuickSight provisioning"
  type        = bool
  default     = false
}

variable "quicksight_account_name" {
  description = "QuickSight account name (required when enabling account subscription)"
  type        = string
  default     = ""
}

variable "quicksight_notification_email" {
  description = "Notification email for QuickSight account subscription and admin user"
  type        = string
  default     = ""
}

variable "quicksight_admin_email" {
  description = "Email for the QuickSight admin/author user"
  type        = string
  default     = ""
}

variable "quicksight_admin_user_name" {
  description = "User name for the QuickSight admin/author user"
  type        = string
  default     = ""
}

variable "quicksight_admin_user_role" {
  description = "Role for the QuickSight admin user (ADMIN, AUTHOR, READER)"
  type        = string
  default     = "AUTHOR"
}

variable "quicksight_identity_type" {
  description = "Identity type for the QuickSight user (QUICKSIGHT, IAM, IAM_IDENTITY_CENTER)"
  type        = string
  default     = "QUICKSIGHT"
}

variable "quicksight_namespace" {
  description = "QuickSight namespace to target (default)"
  type        = string
  default     = "default"
}

variable "quicksight_authentication_method" {
  description = "QuickSight authentication method (IAM_AND_QUICKSIGHT, IAM_ONLY, IAM_IDENTITY_CENTER)"
  type        = string
  default     = "IAM_AND_QUICKSIGHT"
}

variable "quicksight_edition" {
  description = "QuickSight edition (STANDARD, ENTERPRISE, ENTERPRISE_AND_Q)"
  type        = string
  default     = "ENTERPRISE"
}

variable "quicksight_authors_group_name" {
  description = "Custom name for the QuickSight authors group"
  type        = string
  default     = ""
}

variable "quicksight_readers_group_name" {
  description = "Custom name for the QuickSight readers group"
  type        = string
  default     = ""
}

variable "quicksight_data_source_id" {
  description = "Custom identifier for the QuickSight Athena data source"
  type        = string
  default     = ""
}

variable "quicksight_data_source_name" {
  description = "Custom display name for the QuickSight Athena data source"
  type        = string
  default     = ""
}

