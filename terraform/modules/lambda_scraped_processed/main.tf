# ============================================================================
# Lambda Module - Wikipedia Scraper Function
# ============================================================================
# Creates Lambda function infrastructure for web scraping
# Note: Python implementation scripts are NOT included (to be implemented later)

# ----------------------------------------------------------------------------
# Lambda Functions
# ----------------------------------------------------------------------------
# NOTE: Wikipedia scraper Lambda removed - not implemented
# Only the scraped_processor Lambda (container-based) is active

# ----------------------------------------------------------------------------
# Scraped Data Processor Lambda Function
# ----------------------------------------------------------------------------

# Lambda function using container image from ECR
resource "aws_lambda_function" "scraped_processor" {
  function_name = "${var.resource_prefix}-scraped-processor"
  role          = var.lambda_role_arn
  package_type  = "Image"
  image_uri     = "${var.ecr_repository_url}:latest"
  timeout       = 300  # 5 minutes
  memory_size   = 1024  # 1 GB for pandas processing

  environment {
    variables = {
      RAW_BUCKET    = var.raw_bucket_name
      SILVER_BUCKET = var.silver_bucket_name
      DLQ_BUCKET    = var.dlq_bucket_name
    }
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.resource_prefix}-scraped-processor"
    }
  )
}

# CloudWatch Log Group for Scraped Processor Lambda
resource "aws_cloudwatch_log_group" "scraped_processor" {
  name              = "/aws/lambda/${aws_lambda_function.scraped_processor.function_name}"
  retention_in_days = 14

  tags = var.tags
}

# Lambda permission to allow S3 to invoke
resource "aws_lambda_permission" "allow_s3" {
  statement_id  = "AllowExecutionFromS3"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.scraped_processor.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = "arn:aws:s3:::${var.raw_bucket_name}"
}

# S3 bucket notification to trigger Lambda on new scraped data
resource "aws_s3_bucket_notification" "scraped_data_trigger" {
  bucket = var.raw_bucket_name

  # Trigger on weather data
  lambda_function {
    lambda_function_arn = aws_lambda_function.scraped_processor.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "scraped/weather/"
    filter_suffix       = ".json"
  }

  # Trigger on flight data
  lambda_function {
    lambda_function_arn = aws_lambda_function.scraped_processor.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "scraped/flights/"
    filter_suffix       = ".json"
  }

  depends_on = [aws_lambda_permission.allow_s3]
}

