# ============================================================================
# Glue Module - ETL Jobs, Crawlers, Database, and Workflow
# ============================================================================
# Creates Glue resources for data processing pipeline

# ----------------------------------------------------------------------------
# Glue Catalog Database
# ----------------------------------------------------------------------------

resource "aws_glue_catalog_database" "flight_delays" {
  name        = "${var.resource_prefix}-db"
  description = "Database for flight delays data pipeline"

  tags = var.tags
}

# ----------------------------------------------------------------------------
# S3 Bucket for Glue Scripts
# ----------------------------------------------------------------------------

# Upload Glue scripts to S3
resource "aws_s3_object" "data_cleaning_script" {
  bucket = var.raw_bucket_name
  key    = "glue-scripts/data_cleaning.py"
  source = "${path.module}/scripts/data_cleaning.py"
  etag   = filemd5("${path.module}/scripts/data_cleaning.py")
}

resource "aws_s3_object" "feature_engineering_script" {
  bucket = var.raw_bucket_name
  key    = "glue-scripts/feature_engineering.py"
  source = "${path.module}/scripts/feature_engineering.py"
  etag   = filemd5("${path.module}/scripts/feature_engineering.py")
}

# ----------------------------------------------------------------------------
# Glue Job 1: Data Cleaning & Validation
# ----------------------------------------------------------------------------

resource "aws_glue_job" "data_cleaning" {
  name              = "${var.resource_prefix}-data-cleaning"
  role_arn          = var.glue_role_arn
  glue_version      = var.glue_version
  worker_type       = "G.1X"
  number_of_workers = var.cleaning_worker_count
  timeout           = var.cleaning_timeout
  max_retries       = 1

  command {
    name            = "glueetl"
    script_location = "s3://${var.raw_bucket_name}/glue-scripts/data_cleaning.py"
    python_version  = "3"
  }

  default_arguments = {
    "--job-language"                     = "python"
    "--job-bookmark-option"              = "job-bookmark-enable"
    "--enable-metrics"                   = "true"
    "--enable-continuous-cloudwatch-log" = "true"
    "--enable-spark-ui"                  = "true"
    "--spark-event-logs-path"            = "s3://${var.raw_bucket_name}/glue-logs/spark-ui/"
    "--TempDir"                          = "s3://${var.raw_bucket_name}/glue-temp/"
    
    # Custom arguments for the job
    "--RAW_BUCKET"    = var.raw_bucket_name
    "--SILVER_BUCKET" = var.silver_bucket_name
    "--DLQ_BUCKET"    = var.dlq_bucket_name
    "--DATABASE_NAME" = aws_glue_catalog_database.flight_delays.name
  }

  execution_property {
    max_concurrent_runs = 1
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.resource_prefix}-data-cleaning"
    }
  )

  depends_on = [aws_s3_object.data_cleaning_script]
}

# ----------------------------------------------------------------------------
# Glue Job 2: Feature Engineering
# ----------------------------------------------------------------------------

resource "aws_glue_job" "feature_engineering" {
  name              = "${var.resource_prefix}-feature-engineering"
  role_arn          = var.glue_role_arn
  glue_version      = var.glue_version
  worker_type       = "G.1X"
  number_of_workers = var.feature_worker_count
  timeout           = var.feature_timeout
  max_retries       = 1

  command {
    name            = "glueetl"
    script_location = "s3://${var.raw_bucket_name}/glue-scripts/feature_engineering.py"
    python_version  = "3"
  }

  default_arguments = {
    "--job-language"                     = "python"
    "--job-bookmark-option"              = "job-bookmark-enable"
    "--enable-metrics"                   = "true"
    "--enable-continuous-cloudwatch-log" = "true"
    "--enable-spark-ui"                  = "true"
    "--spark-event-logs-path"            = "s3://${var.raw_bucket_name}/glue-logs/spark-ui/"
    "--TempDir"                          = "s3://${var.raw_bucket_name}/glue-temp/"
    
    # Custom arguments for the job
    "--SILVER_BUCKET" = var.silver_bucket_name
    "--GOLD_BUCKET"   = var.gold_bucket_name
    "--DLQ_BUCKET"    = var.dlq_bucket_name
    "--DATABASE_NAME" = aws_glue_catalog_database.flight_delays.name
  }

  execution_property {
    max_concurrent_runs = 1
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.resource_prefix}-feature-engineering"
    }
  )

  depends_on = [aws_s3_object.feature_engineering_script]
}

# ----------------------------------------------------------------------------
# Glue Workflow - Chain Jobs Together
# ----------------------------------------------------------------------------

resource "aws_glue_workflow" "pipeline" {
  name        = "${var.resource_prefix}-workflow"
  description = "Workflow to chain data cleaning and feature engineering jobs"

  tags = var.tags
}

resource "aws_glue_trigger" "start_cleaning" {
  name          = "${var.resource_prefix}-start-cleaning"
  type          = "ON_DEMAND"
  workflow_name = aws_glue_workflow.pipeline.name

  actions {
    job_name = aws_glue_job.data_cleaning.name
  }

  tags = var.tags
}

resource "aws_glue_trigger" "start_feature_engineering" {
  name          = "${var.resource_prefix}-start-feature-engineering"
  type          = "CONDITIONAL"
  workflow_name = aws_glue_workflow.pipeline.name

  predicate {
    conditions {
      job_name = aws_glue_job.data_cleaning.name
      state    = "SUCCEEDED"
    }
  }

  actions {
    job_name = aws_glue_job.feature_engineering.name
  }

  tags = var.tags
}

# ----------------------------------------------------------------------------
# Glue Crawlers
# ----------------------------------------------------------------------------
# NOTE: EventBridge rule for scraped data processing removed.
# Now using S3 event notifications directly in Lambda module for simpler architecture.

# Crawler for Raw bucket
resource "aws_glue_crawler" "raw" {
  name          = "${var.resource_prefix}-raw-crawler"
  role          = var.glue_role_arn
  database_name = aws_glue_catalog_database.flight_delays.name

  s3_target {
    path = "s3://${var.raw_bucket_name}/"
  }

  schema_change_policy {
    delete_behavior = "LOG"
    update_behavior = "UPDATE_IN_DATABASE"
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.resource_prefix}-raw-crawler"
    }
  )
}

# Crawler for Silver bucket
resource "aws_glue_crawler" "silver" {
  name          = "${var.resource_prefix}-silver-crawler"
  role          = var.glue_role_arn
  database_name = aws_glue_catalog_database.flight_delays.name

  s3_target {
    path = "s3://${var.silver_bucket_name}/"
  }

  schema_change_policy {
    delete_behavior = "LOG"
    update_behavior = "UPDATE_IN_DATABASE"
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.resource_prefix}-silver-crawler"
    }
  )
}

# Crawler for Gold bucket
resource "aws_glue_crawler" "gold" {
  name          = "${var.resource_prefix}-gold-crawler"
  role          = var.glue_role_arn
  database_name = aws_glue_catalog_database.flight_delays.name

  s3_target {
    path = "s3://${var.gold_bucket_name}/"
  }

  schema_change_policy {
    delete_behavior = "LOG"
    update_behavior = "UPDATE_IN_DATABASE"
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.resource_prefix}-gold-crawler"
    }
  )
}

