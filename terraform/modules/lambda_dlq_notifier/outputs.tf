output "lambda_function_arn" {
  description = "ARN of the DLQ notifier Lambda function"
  value       = aws_lambda_function.dlq_notifier.arn
}

output "lambda_function_name" {
  description = "Name of the DLQ notifier Lambda function"
  value       = aws_lambda_function.dlq_notifier.function_name
}
