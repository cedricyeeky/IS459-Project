# ============================================================================
# Notifications Module - SNS and EventBridge Schedules
# ============================================================================
# Creates SNS topic for DLQ alerts and EventBridge schedules for automation

# ----------------------------------------------------------------------------
# SNS Topic for DLQ Alerts
# ----------------------------------------------------------------------------

resource "aws_sns_topic" "dlq_alerts" {
  name              = "${var.resource_prefix}-dlq-alerts"
  display_name      = "Flight Delays DLQ Alerts"
  kms_master_key_id = "alias/aws/sns"

  tags = merge(
    var.tags,
    {
      Name = "${var.resource_prefix}-dlq-alerts"
    }
  )
}

# SNS Topic Policy to allow S3 to publish
resource "aws_sns_topic_policy" "dlq_alerts" {
  arn = aws_sns_topic.dlq_alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
        Action   = "SNS:Publish"
        Resource = aws_sns_topic.dlq_alerts.arn
      }
    ]
  })
}

# Email subscription for alerts
resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.dlq_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# ----------------------------------------------------------------------------
# EventBridge Scheduler for Lambda Scraper
# ----------------------------------------------------------------------------

resource "aws_cloudwatch_event_rule" "lambda_schedule" {
  name                = "${var.resource_prefix}-lambda-schedule"
  description         = "Trigger Lambda scraper weekly on Saturdays at 11 PM UTC"
  schedule_expression = var.scraping_schedule

  tags = var.tags
}

resource "aws_cloudwatch_event_target" "lambda" {
  rule      = aws_cloudwatch_event_rule.lambda_schedule.name
  target_id = "LambdaTarget"
  arn       = var.lambda_function_arn
}

# Permission for EventBridge to invoke Lambda
resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = var.lambda_function_arn
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.lambda_schedule.arn
}

# ----------------------------------------------------------------------------
# EventBridge Scheduler for Glue Cleaning Job
# ----------------------------------------------------------------------------

resource "aws_cloudwatch_event_rule" "cleaning_schedule" {
  name                = "${var.resource_prefix}-cleaning-schedule"
  description         = "Trigger Glue cleaning job weekly on Sundays at 1 AM UTC"
  schedule_expression = var.cleaning_schedule

  tags = var.tags
}

resource "aws_cloudwatch_event_target" "cleaning_job" {
  rule      = aws_cloudwatch_event_rule.cleaning_schedule.name
  target_id = "GlueCleaningTarget"
  arn       = var.glue_workflow_arn
  role_arn  = aws_iam_role.eventbridge_glue.arn
}

# ----------------------------------------------------------------------------
# EventBridge Scheduler for Glue Crawlers
# ----------------------------------------------------------------------------

resource "aws_cloudwatch_event_rule" "crawler_schedule" {
  name                = "${var.resource_prefix}-crawler-schedule"
  description         = "Trigger Glue crawlers weekly on Sundays at 2 AM UTC"
  schedule_expression = var.crawler_schedule

  tags = var.tags
}

# Target for Raw crawler
resource "aws_cloudwatch_event_target" "raw_crawler" {
  rule      = aws_cloudwatch_event_rule.crawler_schedule.name
  target_id = "RawCrawlerTarget"
  arn       = "arn:aws:glue:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:crawler/${var.raw_crawler_name}"
  role_arn  = aws_iam_role.eventbridge_glue.arn
}

# Target for Silver crawler
resource "aws_cloudwatch_event_target" "silver_crawler" {
  rule      = aws_cloudwatch_event_rule.crawler_schedule.name
  target_id = "SilverCrawlerTarget"
  arn       = "arn:aws:glue:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:crawler/${var.silver_crawler_name}"
  role_arn  = aws_iam_role.eventbridge_glue.arn
}

# Target for Gold crawler
resource "aws_cloudwatch_event_target" "gold_crawler" {
  rule      = aws_cloudwatch_event_rule.crawler_schedule.name
  target_id = "GoldCrawlerTarget"
  arn       = "arn:aws:glue:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:crawler/${var.gold_crawler_name}"
  role_arn  = aws_iam_role.eventbridge_glue.arn
}

# ----------------------------------------------------------------------------
# IAM Role for EventBridge to Trigger Glue
# ----------------------------------------------------------------------------

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

resource "aws_iam_role" "eventbridge_glue" {
  name = "${var.resource_prefix}-eventbridge-glue-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "eventbridge_glue" {
  name = "${var.resource_prefix}-eventbridge-glue-policy"
  role = aws_iam_role.eventbridge_glue.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "glue:StartWorkflowRun",
          "glue:StartCrawler"
        ]
        Resource = "*"
      }
    ]
  })
}

