# ============================================================================
# Glue Module - Outputs
# ============================================================================

output "database_name" {
  description = "Name of the Glue catalog database"
  value       = aws_glue_catalog_database.flight_delays.name
}

output "cleaning_job_name" {
  description = "Name of the data cleaning Glue job"
  value       = aws_glue_job.data_cleaning.name
}

output "feature_job_name" {
  description = "Name of the feature engineering Glue job"
  value       = aws_glue_job.feature_engineering.name
}

output "workflow_name" {
  description = "Name of the Glue workflow"
  value       = aws_glue_workflow.pipeline.name
}

output "workflow_arn" {
  description = "ARN of the Glue workflow"
  value       = aws_glue_workflow.pipeline.arn
}

output "raw_crawler_name" {
  description = "Name of the raw data crawler"
  value       = aws_glue_crawler.raw.name
}

output "silver_crawler_name" {
  description = "Name of the silver data crawler"
  value       = aws_glue_crawler.silver.name
}

output "gold_crawler_name" {
  description = "Name of the gold data crawler"
  value       = aws_glue_crawler.gold.name
}


