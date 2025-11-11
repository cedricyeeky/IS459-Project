# ============================================================================
# Glue Crawlers for Real-Time Data (Scraped Flights & Weather)
# ============================================================================
# Creates Glue Crawlers to discover schema and create tables for scraped data
# in the Silver bucket, enabling hybrid queries that combine historical + real-time

# ----------------------------------------------------------------------------
# Crawler for Scraped Flight Data
# ----------------------------------------------------------------------------

resource "aws_glue_crawler" "realtime_flights" {
  name          = "${var.resource_prefix}-realtime-flights-crawler"
  role          = var.glue_role_arn
  database_name = aws_glue_catalog_database.flight_delays.name
  description   = "Crawler for real-time scraped flight data from Lambda/EventBridge"

  s3_target {
    path = "s3://${var.silver_bucket_name}/scraped/flights/"
  }

  configuration = jsonencode({
    Version = 1.0
    CrawlerOutput = {
      Partitions = { AddOrUpdateBehavior = "InheritFromTable" }
      Tables     = { AddOrUpdateBehavior = "MergeNewColumns" }
    }
    Grouping = {
      TableGroupingPolicy = "CombineCompatibleSchemas"
    }
  })

  schema_change_policy {
    delete_behavior = "LOG"
    update_behavior = "UPDATE_IN_DATABASE"
  }

  recrawl_policy {
    recrawl_behavior = "CRAWL_NEW_FOLDERS_ONLY"
  }

  # Schedule to run every hour (real-time data arrives every 15 min)
  schedule = "cron(0 * * * ? *)"

  tags = merge(
    var.tags,
    {
      Name        = "${var.resource_prefix}-realtime-flights-crawler"
      DataSource  = "scraped_flights"
      Purpose     = "real-time-analysis"
      QueryType   = "hybrid"
    }
  )
}

# ----------------------------------------------------------------------------
# Crawler for Scraped Weather Data
# ----------------------------------------------------------------------------

resource "aws_glue_crawler" "realtime_weather" {
  name          = "${var.resource_prefix}-realtime-weather-crawler"
  role          = var.glue_role_arn
  database_name = aws_glue_catalog_database.flight_delays.name
  description   = "Crawler for real-time scraped weather data from Lambda/EventBridge"

  s3_target {
    path = "s3://${var.silver_bucket_name}/scraped/weather/"
  }

  configuration = jsonencode({
    Version = 1.0
    CrawlerOutput = {
      Partitions = { AddOrUpdateBehavior = "InheritFromTable" }
      Tables     = { AddOrUpdateBehavior = "MergeNewColumns" }
    }
    Grouping = {
      TableGroupingPolicy = "CombineCompatibleSchemas"
    }
  })

  schema_change_policy {
    delete_behavior = "LOG"
    update_behavior = "UPDATE_IN_DATABASE"
  }

  recrawl_policy {
    recrawl_behavior = "CRAWL_NEW_FOLDERS_ONLY"
  }

  # Schedule to run every hour (real-time data arrives every 15 min)
  schedule = "cron(0 * * * ? *)"

  tags = merge(
    var.tags,
    {
      Name        = "${var.resource_prefix}-realtime-weather-crawler"
      DataSource  = "scraped_weather"
      Purpose     = "real-time-analysis"
      QueryType   = "hybrid"
    }
  )
}

# ----------------------------------------------------------------------------
# Outputs
# ----------------------------------------------------------------------------

output "realtime_flights_crawler_name" {
  description = "Name of the real-time flights crawler"
  value       = aws_glue_crawler.realtime_flights.name
}

output "realtime_weather_crawler_name" {
  description = "Name of the real-time weather crawler"
  value       = aws_glue_crawler.realtime_weather.name
}

output "realtime_flights_crawler_arn" {
  description = "ARN of the real-time flights crawler"
  value       = aws_glue_crawler.realtime_flights.arn
}

output "realtime_weather_crawler_arn" {
  description = "ARN of the real-time weather crawler"
  value       = aws_glue_crawler.realtime_weather.arn
}
