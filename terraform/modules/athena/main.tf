# ============================================================================
# Athena Module - Analytics Query Layer
# ============================================================================
# Creates Athena workgroup and named queries for Phase 1 analytics

# ----------------------------------------------------------------------------
# Athena Workgroup
# ----------------------------------------------------------------------------

resource "aws_athena_workgroup" "flight_delays" {
  name        = "${var.resource_prefix}-workgroup"
  description = "Workgroup for flight delay cascade analysis queries"
  state       = "ENABLED"
  
  force_destroy = true  # Allow deletion even if queries exist

  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true
    bytes_scanned_cutoff_per_query     = var.bytes_scanned_cutoff_per_query

    result_configuration {
      output_location = "s3://${var.raw_bucket_name}/athena-results/"

      encryption_configuration {
        encryption_option = "SSE_S3"
      }
    }

    engine_version {
      selected_engine_version = "Athena engine version 3"
    }
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.resource_prefix}-athena-workgroup"
    }
  )
}

# ----------------------------------------------------------------------------
# Named Query 1: WHEN do delays begin?
# ----------------------------------------------------------------------------

resource "aws_athena_named_query" "when_delays_begin" {
  name      = "${var.resource_prefix}-when-delays-begin"
  workgroup = aws_athena_workgroup.flight_delays.id
  database  = var.database_name
  
  description = "Phase 1 Analytics: Temporal patterns - peak delay hours, seasonal trends, holiday impact"
  
  query = file("${path.module}/queries/when_delays_begin.sql")
}

# ----------------------------------------------------------------------------
# Named Query 2: WHERE do delays begin?
# ----------------------------------------------------------------------------

resource "aws_athena_named_query" "where_delays_begin" {
  name      = "${var.resource_prefix}-where-delays-begin"
  workgroup = aws_athena_workgroup.flight_delays.id
  database  = var.database_name
  
  description = "Phase 1 Analytics: Geographic hotspots - worst airports, routes, hub performance"
  
  query = file("${path.module}/queries/where_delays_begin.sql")
}

# ----------------------------------------------------------------------------
# Named Query 3: WHY do delays begin?
# ----------------------------------------------------------------------------

resource "aws_athena_named_query" "why_delays_begin" {
  name      = "${var.resource_prefix}-why-delays-begin"
  workgroup = aws_athena_workgroup.flight_delays.id
  database  = var.database_name
  
  description = "Phase 1 Analytics: Root cause analysis - weather correlation, holiday × weather interaction"
  
  query = file("${path.module}/queries/why_delays_begin.sql")
}

# ----------------------------------------------------------------------------
# Named Query 4: HOW do delays cascade?
# ----------------------------------------------------------------------------

resource "aws_athena_named_query" "how_delays_cascade" {
  name      = "${var.resource_prefix}-how-delays-cascade"
  workgroup = aws_athena_workgroup.flight_delays.id
  database  = var.database_name
  
  description = "Phase 1 Analytics: Cascade mechanics - aircraft rotation tracking, buffer effectiveness"
  
  query = file("${path.module}/queries/how_delays_cascade.sql")
}

# ----------------------------------------------------------------------------
# Named Query 5: Buffer Recommendations (Operational Tool)
# ----------------------------------------------------------------------------

resource "aws_athena_named_query" "buffer_recommendations" {
  name      = "${var.resource_prefix}-buffer-recommendations"
  workgroup = aws_athena_workgroup.flight_delays.id
  database  = var.database_name
  
  description = "Operational Tool: Generate buffer recommendations for top routes needing increases"
  
  query = file("${path.module}/queries/buffer_recommendations.sql")
}

# ============================================================================
# BQ1: Airline Operations & Efficiency Queries
# ============================================================================

# ----------------------------------------------------------------------------
# Named Query 6: Cascade Probability Matrix & High-Risk Stations
# ----------------------------------------------------------------------------

resource "aws_athena_named_query" "cascade_probability_matrix" {
  name      = "${var.resource_prefix}-cascade-probability-matrix"
  workgroup = aws_athena_workgroup.flight_delays.id
  database  = var.database_name
  
  description = "BQ1: Cascade probability matrices and high-risk station identification (Real-time + Historical)"
  
  query = file("${path.module}/queries/cascade_probability_matrix.sql")
}

# ----------------------------------------------------------------------------
# Named Query 7: Turn Time Optimization with Cost-Benefit Analysis
# ----------------------------------------------------------------------------

resource "aws_athena_named_query" "turn_time_optimization" {
  name      = "${var.resource_prefix}-turn-time-optimization"
  workgroup = aws_athena_workgroup.flight_delays.id
  database  = var.database_name
  
  description = "BQ1: Turn time optimization recommendations with cost-benefit analysis (Real-time + Historical)"
  
  query = file("${path.module}/queries/turn_time_optimization.sql")
}

# ----------------------------------------------------------------------------
# Named Query 8: Root Cause Dashboard
# ----------------------------------------------------------------------------

resource "aws_athena_named_query" "root_cause_dashboard" {
  name      = "${var.resource_prefix}-root-cause-dashboard"
  workgroup = aws_athena_workgroup.flight_delays.id
  database  = var.database_name
  
  description = "BQ1: Root cause dashboards showing delay composition (Real-time + Weather + Historical)"
  
  query = file("${path.module}/queries/root_cause_dashboard.sql")
}

# ----------------------------------------------------------------------------
# Named Query 9: Congestion Patterns & Ground Operations
# ----------------------------------------------------------------------------

resource "aws_athena_named_query" "congestion_patterns" {
  name      = "${var.resource_prefix}-congestion-patterns"
  workgroup = aws_athena_workgroup.flight_delays.id
  database  = var.database_name
  
  description = "BQ1: Congestion patterns and ground operations improvement targets (Real-time + Historical)"
  
  query = file("${path.module}/queries/congestion_patterns.sql")
}

# ============================================================================
# BQ2: Traveler Reliability & Booking Queries
# ============================================================================

# ----------------------------------------------------------------------------
# Named Query 10: Reliability Scores for Routes
# ----------------------------------------------------------------------------

resource "aws_athena_named_query" "reliability_scores" {
  name      = "${var.resource_prefix}-reliability-scores"
  workgroup = aws_athena_workgroup.flight_delays.id
  database  = var.database_name
  
  description = "BQ2: Reliability scores for all major routes with filtering by time/season (Real-time + Historical)"
  
  query = file("${path.module}/queries/reliability_scores.sql")
}

# ----------------------------------------------------------------------------
# Named Query 11: Optimal Departure Windows
# ----------------------------------------------------------------------------

resource "aws_athena_named_query" "optimal_departure_windows" {
  name      = "${var.resource_prefix}-optimal-departure-windows"
  workgroup = aws_athena_workgroup.flight_delays.id
  database  = var.database_name
  
  description = "BQ2: Optimal departure window recommendations (Real-time + Historical)"
  
  query = file("${path.module}/queries/optimal_departure_windows.sql")
}

# ----------------------------------------------------------------------------
# Named Query 12: Carrier Comparison Rankings
# ----------------------------------------------------------------------------

resource "aws_athena_named_query" "carrier_comparison" {
  name      = "${var.resource_prefix}-carrier-comparison"
  workgroup = aws_athena_workgroup.flight_delays.id
  database  = var.database_name
  
  description = "BQ2: Carrier comparison rankings on competitive routes (Real-time + Historical)"
  
  query = file("${path.module}/queries/carrier_comparison.sql")
}

# ----------------------------------------------------------------------------
# Named Query 13: Seasonal Risk Assessment
# ----------------------------------------------------------------------------

resource "aws_athena_named_query" "seasonal_risk_assessment" {
  name      = "${var.resource_prefix}-seasonal-risk-assessment"
  workgroup = aws_athena_workgroup.flight_delays.id
  database  = var.database_name
  
  description = "BQ2: Seasonal risk assessments and weather impact guidance (Real-time + Weather + Historical)"
  
  query = file("${path.module}/queries/seasonal_risk_assessment.sql")
}

# ----------------------------------------------------------------------------
# Named Query 14: Connection Risk Calculator
# ----------------------------------------------------------------------------

resource "aws_athena_named_query" "connection_risk_calculator" {
  name      = "${var.resource_prefix}-connection-risk-calculator"
  workgroup = aws_athena_workgroup.flight_delays.id
  database  = var.database_name
  
  description = "BQ2: Connection risk calculator with minimum buffer recommendations (Real-time + Historical)"
  
  query = file("${path.module}/queries/connection_risk_calculator.sql")
}
