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
