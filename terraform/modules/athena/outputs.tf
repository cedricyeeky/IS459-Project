# ============================================================================
# Athena Module - Outputs
# ============================================================================

output "workgroup_name" {
  description = "Name of the Athena workgroup"
  value       = aws_athena_workgroup.flight_delays.name
}

output "workgroup_id" {
  description = "ID of the Athena workgroup"
  value       = aws_athena_workgroup.flight_delays.id
}

output "query_result_location" {
  description = "S3 location for Athena query results"
  value       = "s3://${var.raw_bucket_name}/athena-results/"
}

output "named_query_ids" {
  description = "Map of named query names to IDs"
  value = {
    when_delays_begin      = aws_athena_named_query.when_delays_begin.id
    where_delays_begin     = aws_athena_named_query.where_delays_begin.id
    why_delays_begin       = aws_athena_named_query.why_delays_begin.id
    how_delays_cascade     = aws_athena_named_query.how_delays_cascade.id
    buffer_recommendations = aws_athena_named_query.buffer_recommendations.id
  }
}
