# ============================================================================
# Lambda DLQ Notifier Module
# ============================================================================
# Creates Lambda function to send SNS notifications when files are added to DLQ

# ----------------------------------------------------------------------------
# Lambda Function Code Archive
# ----------------------------------------------------------------------------

data "archive_file" "lambda" {
  type        = "zip"
  source_file = "${path.module}/lambda_function.py"
  output_path = "${path.module}/lambda_function.zip"
}

# ----------------------------------------------------------------------------
# Lambda Function
# ----------------------------------------------------------------------------

resource "aws_lambda_function" "dlq_notifier" {
  filename         = data.archive_file.lambda.output_path
  function_name    = "${var.resource_prefix}-dlq-notifier"
  role            = aws_iam_role.lambda.arn
  handler         = "lambda_function.lambda_handler"
  source_code_hash = data.archive_file.lambda.output_base64sha256
  runtime         = "python3.11"
  timeout         = 30

  environment {
    variables = {
      SNS_TOPIC_ARN = var.sns_topic_arn
    }
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.resource_prefix}-dlq-notifier"
    }
  )
}

# ----------------------------------------------------------------------------
# Lambda IAM Role
# ----------------------------------------------------------------------------

resource "aws_iam_role" "lambda" {
  name = "${var.resource_prefix}-dlq-notifier-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "lambda" {
  name = "${var.resource_prefix}-dlq-notifier-policy"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = var.sns_topic_arn
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject"
        ]
        Resource = "${var.dlq_bucket_arn}/*"
      }
    ]
  })
}

# ----------------------------------------------------------------------------
# S3 Event Notification to Lambda
# ----------------------------------------------------------------------------

resource "aws_s3_bucket_notification" "dlq_to_lambda" {
  bucket = var.dlq_bucket_name

  lambda_function {
    lambda_function_arn = aws_lambda_function.dlq_notifier.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "scraping_errors/"
  }

  lambda_function {
    lambda_function_arn = aws_lambda_function.dlq_notifier.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "cleaning_errors/"
  }

  lambda_function {
    lambda_function_arn = aws_lambda_function.dlq_notifier.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "feature_eng_errors/"
  }

  lambda_function {
    lambda_function_arn = aws_lambda_function.dlq_notifier.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "lambda_errors/"
  }

  depends_on = [aws_lambda_permission.allow_s3]
}

# ----------------------------------------------------------------------------
# Lambda Permission for S3 to Invoke
# ----------------------------------------------------------------------------

resource "aws_lambda_permission" "allow_s3" {
  statement_id  = "AllowExecutionFromS3"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.dlq_notifier.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = var.dlq_bucket_arn
}
