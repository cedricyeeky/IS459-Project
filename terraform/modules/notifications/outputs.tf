# ============================================================================
# Notifications Module - Outputs
# ============================================================================

output "dlq_sns_topic_arn" {
  description = "ARN of the DLQ alerts SNS topic"
  value       = aws_sns_topic.dlq_alerts.arn
}

output "lambda_schedule_arn" {
  description = "ARN of the Lambda EventBridge schedule"
  value       = aws_cloudwatch_event_rule.lambda_schedule.arn
}

output "cleaning_schedule_arn" {
  description = "ARN of the Glue cleaning job EventBridge schedule"
  value       = aws_cloudwatch_event_rule.cleaning_schedule.arn
}

output "raw_crawler_schedule_arn" {
  description = "ARN of the raw crawler EventBridge Scheduler schedule"
  value       = aws_scheduler_schedule.raw_crawler.arn
}

output "silver_crawler_schedule_arn" {
  description = "ARN of the silver crawler EventBridge Scheduler schedule"
  value       = aws_scheduler_schedule.silver_crawler.arn
}

output "gold_crawler_schedule_arn" {
  description = "ARN of the gold crawler EventBridge Scheduler schedule"
  value       = aws_scheduler_schedule.gold_crawler.arn
}

