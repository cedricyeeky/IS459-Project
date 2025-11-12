# ============================================================================
# QuickSight Module - Variables
# ============================================================================

variable "resource_prefix" {
  description = "Prefix used for naming QuickSight resources"
  type        = string
}

variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string
}

variable "aws_account_id" {
  description = "AWS account ID where QuickSight is deployed"
  type        = string
}

variable "athena_workgroup_name" {
  description = "Name of the Athena workgroup to connect QuickSight to"
  type        = string
}

variable "tags" {
  description = "Common tags applied to QuickSight resources"
  type        = map(string)
  default     = {}
}

variable "quicksight_namespace" {
  description = "QuickSight namespace to use (default)"
  type        = string
  default     = "default"
}

variable "create_account_subscription" {
  description = "Whether to create a QuickSight account subscription (run once per account)"
  type        = bool
  default     = false
}

variable "quicksight_account_name" {
  description = "QuickSight account name (required when create_account_subscription is true)"
  type        = string
  default     = ""
}

variable "quicksight_notification_email" {
  description = "Email address for QuickSight account notifications"
  type        = string
  default     = ""
}

variable "quicksight_edition" {
  description = "QuickSight edition (STANDARD, ENTERPRISE, ENTERPRISE_AND_Q)"
  type        = string
  default     = "ENTERPRISE"
}

variable "authentication_method" {
  description = "Authentication method for QuickSight (IAM_AND_QUICKSIGHT, IAM_ONLY, IAM_IDENTITY_CENTER)"
  type        = string
  default     = "IAM_AND_QUICKSIGHT"
}

variable "provision_admin_user" {
  description = "Whether to provision a QuickSight admin/author user"
  type        = bool
  default     = true
}

variable "quicksight_admin_email" {
  description = "Email address for the QuickSight admin/author user"
  type        = string
  default     = ""
}

variable "quicksight_identity_type" {
  description = "Identity type for the QuickSight user (QUICKSIGHT, IAM, IAM_IDENTITY_CENTER)"
  type        = string
  default     = "QUICKSIGHT"
}

variable "quicksight_admin_user_name" {
  description = "User name for the QuickSight admin/author"
  type        = string
  default     = ""
}

variable "quicksight_admin_user_role" {
  description = "Role for the QuickSight admin user (ADMIN, AUTHOR, READER)"
  type        = string
  default     = "AUTHOR"
}

variable "authors_group_name" {
  description = "Override for QuickSight authors group name"
  type        = string
  default     = ""
}

variable "readers_group_name" {
  description = "Override for QuickSight readers group name"
  type        = string
  default     = ""
}

variable "data_source_id" {
  description = "Override for the QuickSight data source ID"
  type        = string
  default     = ""
}

variable "data_source_name" {
  description = "Override for the QuickSight data source name"
  type        = string
  default     = ""
}


