# ============================================================================
# Scraper Module - EventBridge Scheduled ECS Task
# ============================================================================
# Creates EventBridge rule, ECS task definition, and IAM roles for scraper

# ----------------------------------------------------------------------------
# CloudWatch Log Group for Scraper
# ----------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "scraper" {
  name              = "/ecs/${var.project_name}-${var.environment}/scraper"
  retention_in_days = 7

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-scraper-logs"
      Environment = var.environment
    }
  )
}

# ----------------------------------------------------------------------------
# IAM Role for Scraper ECS Task Execution
# ----------------------------------------------------------------------------

resource "aws_iam_role" "scraper_execution" {
  name = "${var.project_name}-${var.environment}-scraper-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-scraper-execution-role"
      Environment = var.environment
    }
  )
}

resource "aws_iam_role_policy_attachment" "scraper_execution" {
  role       = aws_iam_role.scraper_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ----------------------------------------------------------------------------
# IAM Role for Scraper ECS Task (Application Role)
# ----------------------------------------------------------------------------

resource "aws_iam_role" "scraper_task" {
  name = "${var.project_name}-${var.environment}-scraper-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-scraper-task-role"
      Environment = var.environment
    }
  )
}

# IAM Policy for S3 Access
resource "aws_iam_role_policy" "scraper_s3_access" {
  name = "${var.project_name}-${var.environment}-scraper-s3-policy"
  role = aws_iam_role.scraper_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:PutObjectAcl",
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          "${var.raw_bucket_arn}",
          "${var.raw_bucket_arn}/*"
        ]
      }
    ]
  })
}

# ----------------------------------------------------------------------------
# ECS Task Definition for Scraper
# ----------------------------------------------------------------------------

resource "aws_ecs_task_definition" "scraper" {
  family                   = "${var.project_name}-${var.environment}-scraper"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.scraper_cpu
  memory                   = var.scraper_memory
  execution_role_arn       = aws_iam_role.scraper_execution.arn
  task_role_arn            = aws_iam_role.scraper_task.arn

  container_definitions = jsonencode([
    {
      name      = "scraper"
      image     = var.scraper_image
      essential = true

      environment = [
        {
          name  = "API_ENDPOINT"
          value = var.api_endpoint
        },
        {
          name  = "S3_BUCKET"
          value = var.raw_bucket_name
        },
        {
          name  = "AWS_REGION"
          value = var.aws_region
        },
        {
          name  = "REQUEST_TIMEOUT"
          value = "30"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.scraper.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "scraper"
        }
      }
    }
  ])

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-scraper"
      Environment = var.environment
    }
  )
}

# ----------------------------------------------------------------------------
# IAM Role for EventBridge to Run ECS Task
# ----------------------------------------------------------------------------

resource "aws_iam_role" "eventbridge_ecs" {
  name = "${var.project_name}-${var.environment}-eventbridge-ecs-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-eventbridge-ecs-role"
      Environment = var.environment
    }
  )
}

resource "aws_iam_role_policy" "eventbridge_ecs_run_task" {
  name = "${var.project_name}-${var.environment}-eventbridge-ecs-policy"
  role = aws_iam_role.eventbridge_ecs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecs:RunTask"
        ]
        Resource = [
          aws_ecs_task_definition.scraper.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "iam:PassRole"
        ]
        Resource = [
          aws_iam_role.scraper_execution.arn,
          aws_iam_role.scraper_task.arn
        ]
      }
    ]
  })
}

# ----------------------------------------------------------------------------
# EventBridge Rule for Scheduled Scraping
# ----------------------------------------------------------------------------

resource "aws_cloudwatch_event_rule" "scraper_schedule" {
  name                = "${var.project_name}-${var.environment}-scraper-schedule"
  description         = "Trigger scraper to fetch weather and flight data every 15 minutes"
  schedule_expression = var.scraper_schedule_expression

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-${var.environment}-scraper-schedule"
      Environment = var.environment
    }
  )
}

resource "aws_cloudwatch_event_target" "scraper_ecs" {
  rule      = aws_cloudwatch_event_rule.scraper_schedule.name
  target_id = "scraper-ecs-task"
  arn       = var.ecs_cluster_arn
  role_arn  = aws_iam_role.eventbridge_ecs.arn

  ecs_target {
    task_count          = 1
    task_definition_arn = aws_ecs_task_definition.scraper.arn
    launch_type         = "FARGATE"
    platform_version    = "LATEST"

    network_configuration {
      subnets          = var.private_subnet_ids
      security_groups  = [var.scraper_security_group_id]
      assign_public_ip = false
    }
  }
}
