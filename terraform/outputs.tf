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
# NOTE: Wikipedia scraper Lambda outputs removed - function removed

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

# NOTE: lambda_schedule_arn removed - Wikipedia Lambda schedule removed

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
# Athena Outputs (Phase 1)
# ----------------------------------------------------------------------------

output "athena_workgroup_name" {
  description = "Name of the Athena workgroup for Phase 1 analytics"
  value       = module.athena.workgroup_name
}

output "athena_query_result_location" {
  description = "S3 location for Athena query results"
  value       = module.athena.query_result_location
}

output "athena_named_queries" {
  description = "Map of named query names to IDs"
  value       = module.athena.named_query_ids
}

# ----------------------------------------------------------------------------
# QuickSight Outputs
# ----------------------------------------------------------------------------

output "quicksight_data_source_arn" {
  description = "ARN of the QuickSight Athena data source"
  value       = length(module.quicksight) > 0 ? module.quicksight[0].data_source_arn : null
}

output "quicksight_authors_group_arn" {
  description = "ARN of the QuickSight authors group"
  value       = length(module.quicksight) > 0 ? module.quicksight[0].authors_group_arn : null
}

output "quicksight_readers_group_arn" {
  description = "ARN of the QuickSight readers group"
  value       = length(module.quicksight) > 0 ? module.quicksight[0].readers_group_arn : null
}

output "quicksight_admin_user_name" {
  description = "QuickSight admin/author user name if provisioned"
  value       = length(module.quicksight) > 0 ? module.quicksight[0].admin_user_name : null
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

# ----------------------------------------------------------------------------
# Network Outputs (Mock API / Scraper ECS)
# ----------------------------------------------------------------------------

output "vpc_id" {
  description = "VPC ID"
  value       = var.vpc_id != "" ? var.vpc_id : module.vpc[0].vpc_id
}

output "private_subnet_ids" {
  description = "Private subnet IDs"
  value       = var.vpc_id != "" ? data.aws_subnets.private[0].ids : module.vpc[0].private_subnets
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = var.vpc_id != "" ? data.aws_subnets.public[0].ids : module.vpc[0].public_subnets
}

# ----------------------------------------------------------------------------
# ECR Outputs
# ----------------------------------------------------------------------------

output "mock_api_ecr_repository_url" {
  description = "ECR repository URL for mock API"
  value       = aws_ecr_repository.mock_api.repository_url
}

output "scraper_ecr_repository_url" {
  description = "ECR repository URL for scraper"
  value       = aws_ecr_repository.scraper.repository_url
}

# ----------------------------------------------------------------------------
# ECS Outputs
# ----------------------------------------------------------------------------

output "ecs_cluster_id" {
  description = "ECS Cluster ID"
  value       = module.mock_api_ecs.ecs_cluster_id
}

output "ecs_cluster_name" {
  description = "ECS Cluster name"
  value       = module.mock_api_ecs.ecs_cluster_name
}

output "mock_api_service_name" {
  description = "Mock API ECS Service name"
  value       = module.mock_api_ecs.mock_api_service_name
}

# ----------------------------------------------------------------------------
# Load Balancer Outputs
# ----------------------------------------------------------------------------

output "alb_dns_name" {
  description = "Application Load Balancer DNS name"
  value       = module.mock_api_ecs.alb_dns_name
}

output "alb_url" {
  description = "Full URL to access the Mock API"
  value       = module.mock_api_ecs.alb_url
}

output "mock_api_endpoint" {
  description = "Mock API endpoint for realtime flights"
  value       = module.mock_api_ecs.mock_api_endpoint
}

output "alb_zone_id" {
  description = "ALB Zone ID for Route53 alias records"
  value       = module.mock_api_ecs.alb_zone_id
}

# ----------------------------------------------------------------------------
# CloudWatch Log Groups
# ----------------------------------------------------------------------------

output "mock_api_log_group" {
  description = "CloudWatch Log Group for Mock API"
  value       = module.mock_api_ecs.mock_api_log_group
}

output "scraper_log_group" {
  description = "CloudWatch Log Group for Scraper"
  value       = module.scraper_ecs.scraper_log_group_name
}

# ----------------------------------------------------------------------------
# Scraper Outputs
# ----------------------------------------------------------------------------

output "scraper_task_definition_arn" {
  description = "ARN of the scraper ECS task definition"
  value       = module.scraper_ecs.scraper_task_definition_arn
}

output "eventbridge_rule_name" {
  description = "Name of the EventBridge rule for scraper"
  value       = module.scraper_ecs.eventbridge_rule_name
}

output "scraper_schedule" {
  description = "Schedule expression for the scraper"
  value       = module.scraper_ecs.scraper_schedule
}

