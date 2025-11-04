# ============================================================================
# Flight Delays Data Pipeline - Outputs
# ============================================================================

# ----------------------------------------------------------------------------
# S3 Bucket Outputs
# ----------------------------------------------------------------------------

output "raw_bucket_name" {
  description = "Name of the raw data S3 bucket"
  value       = module.s3.raw_bucket_name
}

output "raw_bucket_arn" {
  description = "ARN of the raw data S3 bucket"
  value       = module.s3.raw_bucket_arn
}

output "silver_bucket_name" {
  description = "Name of the silver data S3 bucket"
  value       = module.s3.silver_bucket_name
}

output "silver_bucket_arn" {
  description = "ARN of the silver data S3 bucket"
  value       = module.s3.silver_bucket_arn
}

output "gold_bucket_name" {
  description = "Name of the gold data S3 bucket"
  value       = module.s3.gold_bucket_name
}

output "gold_bucket_arn" {
  description = "ARN of the gold data S3 bucket"
  value       = module.s3.gold_bucket_arn
}

output "dlq_bucket_name" {
  description = "Name of the DLQ S3 bucket"
  value       = module.s3.dlq_bucket_name
}

output "dlq_bucket_arn" {
  description = "ARN of the DLQ S3 bucket"
  value       = module.s3.dlq_bucket_arn
}

# ----------------------------------------------------------------------------
# Lambda Outputs
# ----------------------------------------------------------------------------

output "lambda_function_name" {
  description = "Name of the Wikipedia scraper Lambda function"
  value       = module.lambda.lambda_function_name
}

output "lambda_function_arn" {
  description = "ARN of the Wikipedia scraper Lambda function"
  value       = module.lambda.lambda_function_arn
}

# ----------------------------------------------------------------------------
# Glue Outputs
# ----------------------------------------------------------------------------

output "glue_database_name" {
  description = "Name of the Glue catalog database"
  value       = module.glue.database_name
}

output "cleaning_job_name" {
  description = "Name of the data cleaning Glue job"
  value       = module.glue.cleaning_job_name
}

output "feature_job_name" {
  description = "Name of the feature engineering Glue job"
  value       = module.glue.feature_job_name
}

output "glue_workflow_name" {
  description = "Name of the Glue workflow"
  value       = module.glue.workflow_name
}

output "raw_crawler_name" {
  description = "Name of the raw data crawler"
  value       = module.glue.raw_crawler_name
}

output "silver_crawler_name" {
  description = "Name of the silver data crawler"
  value       = module.glue.silver_crawler_name
}

output "gold_crawler_name" {
  description = "Name of the gold data crawler"
  value       = module.glue.gold_crawler_name
}

# ----------------------------------------------------------------------------
# Notification Outputs
# ----------------------------------------------------------------------------

output "sns_topic_arn" {
  description = "ARN of the DLQ alerts SNS topic"
  value       = module.notifications.dlq_sns_topic_arn
}

output "lambda_schedule_arn" {
  description = "ARN of the Lambda EventBridge schedule"
  value       = module.notifications.lambda_schedule_arn
}

output "cleaning_schedule_arn" {
  description = "ARN of the Glue cleaning job EventBridge schedule"
  value       = module.notifications.cleaning_schedule_arn
}

output "raw_crawler_schedule_arn" {
  description = "ARN of the raw crawler EventBridge Scheduler schedule"
  value       = module.notifications.raw_crawler_schedule_arn
}

output "silver_crawler_schedule_arn" {
  description = "ARN of the silver crawler EventBridge Scheduler schedule"
  value       = module.notifications.silver_crawler_schedule_arn
}

output "gold_crawler_schedule_arn" {
  description = "ARN of the gold crawler EventBridge Scheduler schedule"
  value       = module.notifications.gold_crawler_schedule_arn
}

# ----------------------------------------------------------------------------
# IAM Outputs
# ----------------------------------------------------------------------------

output "lambda_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = module.iam.lambda_role_arn
}

output "glue_role_arn" {
  description = "ARN of the Glue service role"
  value       = module.iam.glue_role_arn
}

# ----------------------------------------------------------------------------
# Deployment Information
# ----------------------------------------------------------------------------

output "deployment_summary" {
  description = "Summary of deployed resources"
  value = {
    environment     = var.environment
    region          = var.aws_region
    resource_prefix = "${var.resource_prefix}-${var.environment}"
    alert_email     = var.alert_email
  }
}

