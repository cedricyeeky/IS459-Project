# ============================================================================
# Athena Module - Input Variables
# ============================================================================

variable "resource_prefix" {
  description = "Prefix for all resource names"
  type        = string
}

variable "database_name" {
  description = "Glue Catalog database name containing flight delay tables"
  type        = string
}

variable "raw_bucket_name" {
  description = "S3 bucket name for Athena query results"
  type        = string
}

variable "bytes_scanned_cutoff_per_query" {
  description = "Maximum bytes scanned per query (cost control)"
  type        = number
  default     = 10737418240  # 10 GB
}

variable "tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}
