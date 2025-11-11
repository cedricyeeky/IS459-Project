# ============================================================================
# QuickSight Module - Outputs
# ============================================================================

output "authors_group_arn" {
  description = "ARN of the QuickSight authors group"
  value       = aws_quicksight_group.authors.arn
}

output "readers_group_arn" {
  description = "ARN of the QuickSight readers group"
  value       = aws_quicksight_group.readers.arn
}

output "admin_user_name" {
  description = "QuickSight admin/author user name (if provisioned)"
  value       = var.provision_admin_user ? aws_quicksight_user.admin[0].user_name : null
}

output "data_source_arn" {
  description = "ARN of the QuickSight Athena data source"
  value       = aws_quicksight_data_source.athena.arn
}


