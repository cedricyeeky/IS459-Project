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
    # Phase 1 Analytics (Historical)
    when_delays_begin      = aws_athena_named_query.when_delays_begin.id
    where_delays_begin     = aws_athena_named_query.where_delays_begin.id
    why_delays_begin       = aws_athena_named_query.why_delays_begin.id
    how_delays_cascade     = aws_athena_named_query.how_delays_cascade.id
    buffer_recommendations = aws_athena_named_query.buffer_recommendations.id
    
    # BQ1: Airline Operations & Efficiency (Real-time + Historical)
    cascade_probability_matrix = aws_athena_named_query.cascade_probability_matrix.id
    turn_time_optimization     = aws_athena_named_query.turn_time_optimization.id
    root_cause_dashboard       = aws_athena_named_query.root_cause_dashboard.id
    congestion_patterns       = aws_athena_named_query.congestion_patterns.id
    
    # BQ2: Traveler Reliability & Booking (Real-time + Historical)
    reliability_scores         = aws_athena_named_query.reliability_scores.id
    optimal_departure_windows   = aws_athena_named_query.optimal_departure_windows.id
    carrier_comparison          = aws_athena_named_query.carrier_comparison.id
    seasonal_risk_assessment   = aws_athena_named_query.seasonal_risk_assessment.id
    connection_risk_calculator  = aws_athena_named_query.connection_risk_calculator.id
  }
}
