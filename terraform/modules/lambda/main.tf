# ============================================================================
# Lambda Module - Wikipedia Scraper Function
# ============================================================================
# Creates Lambda function infrastructure for web scraping
# Note: Python implementation scripts are NOT included (to be implemented later)

# ----------------------------------------------------------------------------
# Lambda Function
# ----------------------------------------------------------------------------

# Create a placeholder Lambda deployment package
# In production, this would contain the actual scraper.py implementation
data "archive_file" "lambda_placeholder" {
  type        = "zip"
  output_path = "${path.module}/lambda_function.zip"

  source {
    content  = "# Placeholder - implement scraper.py\nprint('Lambda function not yet implemented')"
    filename = "lambda_function.py"
  }
}

resource "aws_lambda_function" "scraper" {
  filename         = data.archive_file.lambda_placeholder.output_path
  function_name    = "${var.resource_prefix}-wikipedia-scraper"
  role             = var.lambda_role_arn
  handler          = "scraper.lambda_handler"
  source_code_hash = data.archive_file.lambda_placeholder.output_base64sha256
  runtime          = "python3.11"
  timeout          = var.lambda_timeout
  memory_size      = var.lambda_memory_size

  environment {
    variables = {
      RAW_BUCKET_NAME = var.raw_bucket_name
      DLQ_BUCKET_NAME = var.dlq_bucket_name
      WIKIPEDIA_URLS  = jsonencode(var.wikipedia_urls)
    }
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.resource_prefix}-wikipedia-scraper"
    }
  )
}

# CloudWatch Log Group for Lambda
resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${aws_lambda_function.scraper.function_name}"
  retention_in_days = 14

  tags = var.tags
}

