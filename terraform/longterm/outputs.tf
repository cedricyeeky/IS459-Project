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

# ============================================
# Deployment Instructions
# ============================================
output "next_steps" {
  description = "Next steps for deployment"
  value = <<-EOT
    
    ====================================================================
    Mock Flight API Deployment Complete! 🚀
    ====================================================================
    
    API Endpoint: ${module.compute.alb_url}
    Realtime Flights: ${module.compute.mock_api_endpoint}
    
    ECS Cluster: ${module.compute.ecs_cluster_name}
    Mock API Service: ${module.compute.mock_api_service_name}
    
    Docker Image Repository:
    - Mock API: ${aws_ecr_repository.mock_api.repository_url}
    
    CloudWatch Logs:
    - Mock API: ${module.compute.mock_api_log_group}
    
    ====================================================================
    Next Steps:
    ====================================================================
    
    1. Build and push Docker image:
       
       # Authenticate with ECR
       aws ecr get-login-password --region ${var.aws_region} | docker login --username AWS --password-stdin ${aws_ecr_repository.mock_api.repository_url}
       
       # Build and push Mock API
       cd mock_api
       docker build -t ${aws_ecr_repository.mock_api.repository_url}:latest .
       docker push ${aws_ecr_repository.mock_api.repository_url}:latest
    
    2. Force new deployment to pick up image:
       
       aws ecs update-service --cluster ${module.compute.ecs_cluster_name} \
         --service ${module.compute.mock_api_service_name} \
         --force-new-deployment --region ${var.aws_region}
    
    3. Test the API:
       
       curl ${module.compute.alb_url}/health
       curl ${module.compute.mock_api_endpoint}
    
    4. Monitor logs:
       
       aws logs tail ${module.compute.mock_api_log_group} --follow --region ${var.aws_region}
    
    ====================================================================
    
  EOT
}
