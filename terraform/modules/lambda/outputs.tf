# ============================================================================
# Lambda Module - Outputs
# ============================================================================
# NOTE: Wikipedia scraper outputs removed - function removed

output "scraped_processor_function_name" {
  description = "Name of the scraped data processor Lambda function"
  value       = aws_lambda_function.scraped_processor.function_name
}

output "scraped_processor_function_arn" {
  description = "ARN of the scraped data processor Lambda function"
  value       = aws_lambda_function.scraped_processor.arn
}

