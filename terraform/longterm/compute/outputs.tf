output "ecs_cluster_id" {
  description = "ECS Cluster ID"
  value       = aws_ecs_cluster.main.id
}

output "ecs_cluster_name" {
  description = "ECS Cluster name"
  value       = aws_ecs_cluster.main.name
}

output "mock_api_service_name" {
  description = "Mock API ECS Service name"
  value       = aws_ecs_service.mock_api.name
}

output "alb_dns_name" {
  description = "Application Load Balancer DNS name"
  value       = aws_lb.main.dns_name
}

output "alb_url" {
  description = "Full URL to access the Mock API"
  value       = "http://${aws_lb.main.dns_name}"
}

output "mock_api_endpoint" {
  description = "Mock API endpoint for realtime flights"
  value       = "http://${aws_lb.main.dns_name}/api/v1/flights/realtime"
}

output "alb_zone_id" {
  description = "ALB Zone ID for Route53 alias records"
  value       = aws_lb.main.zone_id
}

output "ecs_task_execution_role_arn" {
  description = "ECS Task Execution Role ARN"
  value       = aws_iam_role.ecs_task_execution_role.arn
}

output "ecs_task_role_arn" {
  description = "ECS Task Role ARN"
  value       = aws_iam_role.ecs_task_role.arn
}

output "mock_api_log_group" {
  description = "CloudWatch Log Group for Mock API"
  value       = aws_cloudwatch_log_group.mock_api.name
}
