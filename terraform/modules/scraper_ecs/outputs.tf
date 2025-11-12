# ============================================================================
# Scraper Module - Outputs
# ============================================================================

output "scraper_task_definition_arn" {
  description = "ARN of the scraper ECS task definition"
  value       = aws_ecs_task_definition.scraper.arn
}

output "scraper_task_definition_family" {
  description = "Family name of the scraper task definition"
  value       = aws_ecs_task_definition.scraper.family
}

output "scraper_log_group_name" {
  description = "Name of the scraper CloudWatch log group"
  value       = aws_cloudwatch_log_group.scraper.name
}

output "eventbridge_rule_name" {
  description = "Name of the EventBridge rule"
  value       = aws_cloudwatch_event_rule.scraper_schedule.name
}

output "eventbridge_rule_arn" {
  description = "ARN of the EventBridge rule"
  value       = aws_cloudwatch_event_rule.scraper_schedule.arn
}

output "scraper_schedule" {
  description = "Schedule expression for the scraper"
  value       = var.scraper_schedule_expression
}
