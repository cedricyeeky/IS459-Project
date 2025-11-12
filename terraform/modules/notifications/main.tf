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
        Sid    = "AllowS3Publish"
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
        Action   = "SNS:Publish"
        Resource = aws_sns_topic.dlq_alerts.arn
      },
      {
        Sid    = "AllowAccountFullAccess"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${var.aws_account_id}:root"
        }
        Action = [
          "SNS:Publish",
          "SNS:Subscribe",
          "SNS:SetTopicAttributes",
          "SNS:RemovePermission",
          "SNS:Receive",
          "SNS:ListSubscriptionsByTopic",
          "SNS:GetTopicAttributes",
          "SNS:DeleteTopic",
          "SNS:AddPermission"
        ]
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
# NOTE: EventBridge Scheduler for Lambda Scraper REMOVED
# Wikipedia scraper Lambda function was not implemented and has been removed
# ----------------------------------------------------------------------------

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
# Using EventBridge Scheduler (not CloudWatch Events) which supports Glue Crawlers

resource "aws_scheduler_schedule" "raw_crawler" {
  name       = "${var.resource_prefix}-raw-crawler-schedule"
  group_name = "default"

  flexible_time_window {
    mode = "OFF"
  }

  schedule_expression = var.crawler_schedule

  target {
    arn      = "arn:aws:scheduler:::aws-sdk:glue:startCrawler"
    role_arn = aws_iam_role.scheduler_glue.arn

    input = jsonencode({
      Name = var.raw_crawler_name
    })

    retry_policy {
      maximum_event_age_in_seconds = 3600
      maximum_retry_attempts       = 2
    }
  }
}

resource "aws_scheduler_schedule" "silver_crawler" {
  name       = "${var.resource_prefix}-silver-crawler-schedule"
  group_name = "default"

  flexible_time_window {
    mode = "OFF"
  }

  schedule_expression = var.crawler_schedule

  target {
    arn      = "arn:aws:scheduler:::aws-sdk:glue:startCrawler"
    role_arn = aws_iam_role.scheduler_glue.arn

    input = jsonencode({
      Name = var.silver_crawler_name
    })

    retry_policy {
      maximum_event_age_in_seconds = 3600
      maximum_retry_attempts       = 2
    }
  }
}

resource "aws_scheduler_schedule" "gold_crawler" {
  name       = "${var.resource_prefix}-gold-crawler-schedule"
  group_name = "default"

  flexible_time_window {
    mode = "OFF"
  }

  schedule_expression = var.crawler_schedule

  target {
    arn      = "arn:aws:scheduler:::aws-sdk:glue:startCrawler"
    role_arn = aws_iam_role.scheduler_glue.arn

    input = jsonencode({
      Name = var.gold_crawler_name
    })

    retry_policy {
      maximum_event_age_in_seconds = 3600
      maximum_retry_attempts       = 2
    }
  }
}

# ----------------------------------------------------------------------------
# IAM Roles for EventBridge and Scheduler to Trigger Glue
# ----------------------------------------------------------------------------

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Role for EventBridge (CloudWatch Events) to trigger Glue Workflow
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
          "glue:StartWorkflowRun"
        ]
        Resource = "*"
      }
    ]
  })
}

# Role for EventBridge Scheduler to trigger Glue Crawlers
resource "aws_iam_role" "scheduler_glue" {
  name = "${var.resource_prefix}-scheduler-glue-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "scheduler.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "scheduler_glue" {
  name = "${var.resource_prefix}-scheduler-glue-policy"
  role = aws_iam_role.scheduler_glue.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "glue:StartCrawler"
        ]
        Resource = "*"
      }
    ]
  })
}

