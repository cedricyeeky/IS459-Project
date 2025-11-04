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

output "crawler_schedule_arn" {
  description = "ARN of the Glue crawler EventBridge schedule"
  value       = aws_cloudwatch_event_rule.crawler_schedule.arn
}

