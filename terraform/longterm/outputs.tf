# ============================================
# Network Outputs
# ============================================
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

# ============================================
# ECR Outputs
# ============================================
output "mock_api_ecr_repository_url" {
  description = "ECR repository URL for mock API"
  value       = aws_ecr_repository.mock_api.repository_url
}

output "scraper_ecr_repository_url" {
  description = "ECR repository URL for scraper"
  value       = aws_ecr_repository.scraper.repository_url
}

# ============================================
# ECS Outputs
# ============================================
output "ecs_cluster_id" {
  description = "ECS Cluster ID"
  value       = module.compute.ecs_cluster_id
}

output "ecs_cluster_name" {
  description = "ECS Cluster name"
  value       = module.compute.ecs_cluster_name
}

output "mock_api_service_name" {
  description = "Mock API ECS Service name"
  value       = module.compute.mock_api_service_name
}

# ============================================
# Load Balancer Outputs
# ============================================
output "alb_dns_name" {
  description = "Application Load Balancer DNS name"
  value       = module.compute.alb_dns_name
}

output "alb_url" {
  description = "Full URL to access the Mock API"
  value       = module.compute.alb_url
}

output "mock_api_endpoint" {
  description = "Mock API endpoint for realtime flights"
  value       = module.compute.mock_api_endpoint
}

output "alb_zone_id" {
  description = "ALB Zone ID for Route53 alias records"
  value       = module.compute.alb_zone_id
}

# ============================================
# CloudWatch Outputs
# ============================================
output "mock_api_log_group" {
  description = "CloudWatch Log Group for Mock API"
  value       = module.compute.mock_api_log_group
}

output "scraper_log_group" {
  description = "CloudWatch Log Group for Scraper"
  value       = module.scraper.scraper_log_group_name
}

# ============================================
# Scraper Outputs
# ============================================
output "scraper_task_definition_arn" {
  description = "ARN of the scraper ECS task definition"
  value       = module.scraper.scraper_task_definition_arn
}

output "eventbridge_rule_name" {
  description = "Name of the EventBridge rule for scraper"
  value       = module.scraper.eventbridge_rule_name
}

output "scraper_schedule" {
  description = "Schedule expression for the scraper"
  value       = module.scraper.scraper_schedule
}

# ============================================
# Deployment Instructions
# ============================================
output "next_steps" {
  description = "Next steps for deployment"
  value = <<-EOT
    
    ====================================================================
    Mock Flight API + Data Scraper Deployment Complete! 🚀
    ====================================================================
    
    API Endpoint: ${module.compute.alb_url}
    Realtime Flights: ${module.compute.mock_api_endpoint}
    Weather Data: ${module.compute.alb_url}/api/v1/weather
    
    ECS Cluster: ${module.compute.ecs_cluster_name}
    Mock API Service: ${module.compute.mock_api_service_name}
    
    S3 Bucket (Glue Pipeline):
    - Raw Data: flight-delays-dev-raw
    
    Docker Image Repositories:
    - Mock API: ${aws_ecr_repository.mock_api.repository_url}
    - Scraper: ${aws_ecr_repository.scraper.repository_url}
    
    CloudWatch Logs:
    - Mock API: ${module.compute.mock_api_log_group}
    - Scraper: ${module.scraper.scraper_log_group_name}
    
    Scraper Configuration:
    - Schedule: ${module.scraper.scraper_schedule}
    - EventBridge Rule: ${module.scraper.eventbridge_rule_name}
    - Task Definition: ${module.scraper.scraper_task_definition_arn}
    - Target Bucket: flight-delays-dev-raw
    
    ====================================================================
    Next Steps:
    ====================================================================
    
    1. Build and push Docker images:
       
       # Authenticate with ECR
       aws ecr get-login-password --region ${var.aws_region} | docker login --username AWS --password-stdin ${split("/", aws_ecr_repository.mock_api.repository_url)[0]}
       
       # Build and push Mock API
       cd mock_api
       docker build --platform linux/amd64 -t ${aws_ecr_repository.mock_api.repository_url}:latest .
       docker push ${aws_ecr_repository.mock_api.repository_url}:latest
       
       # Build and push Scraper
       cd ../scraper
       docker build --platform linux/amd64 -t ${aws_ecr_repository.scraper.repository_url}:latest .
       docker push ${aws_ecr_repository.scraper.repository_url}:latest
    
    2. Force new deployment to pick up images:
       
       # Mock API
       aws ecs update-service --cluster ${module.compute.ecs_cluster_name} \
         --service ${module.compute.mock_api_service_name} \
         --force-new-deployment --region ${var.aws_region}
    
    3. Test the API:
       
       curl ${module.compute.alb_url}/health
       curl "${module.compute.alb_url}/api/v1/flights/realtime?limit=5"
       curl "${module.compute.alb_url}/api/v1/weather?limit=5"
    
    4. Monitor scraper execution:
       
       # Watch scraper logs
       aws logs tail ${module.scraper.scraper_log_group_name} --follow --region ${var.aws_region}
       
       # Check EventBridge rule
       aws events describe-rule --name ${module.scraper.eventbridge_rule_name} --region ${var.aws_region}
       
       # Manually trigger scraper (for testing)
       aws ecs run-task \
         --cluster ${module.compute.ecs_cluster_name} \
         --task-definition ${module.scraper.scraper_task_definition_arn} \
         --launch-type FARGATE \
         --network-configuration "awsvpcConfiguration={subnets=[${join(",", var.vpc_id != "" ? data.aws_subnets.private[0].ids : module.vpc[0].private_subnets)}],securityGroups=[${module.compute.scraper_security_group_id}],assignPublicIp=DISABLED}" \
         --region ${var.aws_region}
    
    5. Check S3 for scraped data:
       
       # List scraped data in Glue pipeline bucket
       aws s3 ls s3://flight-delays-dev-raw/scraped/ --recursive --region ${var.aws_region}
       
       # View weather data
       aws s3 ls s3://flight-delays-dev-raw/scraped/weather/ --region ${var.aws_region}
       
       # View flights data
       aws s3 ls s3://flight-delays-dev-raw/scraped/flights/ --region ${var.aws_region}
    
    ====================================================================
    
  EOT
}
