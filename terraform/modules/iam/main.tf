# ============================================================================
# IAM Module - Roles and Policies for Lambda and Glue
# ============================================================================
# Creates IAM roles with least privilege access for Lambda and Glue services

# ----------------------------------------------------------------------------
# Lambda Execution Role
# ----------------------------------------------------------------------------

# Trust policy for Lambda service
data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "lambda" {
  name               = "${var.resource_prefix}-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json

  tags = merge(
    var.tags,
    {
      Name = "${var.resource_prefix}-lambda-role"
    }
  )
}

# Lambda S3 access policy
data "aws_iam_policy_document" "lambda_s3" {
  # Read/Write access to Raw bucket
  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:ListBucket"
    ]
    resources = [
      var.raw_bucket_arn,
      "${var.raw_bucket_arn}/*"
    ]
  }

  # Write access to DLQ bucket for error logging
  statement {
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:ListBucket"
    ]
    resources = [
      var.dlq_bucket_arn,
      "${var.dlq_bucket_arn}/*"
    ]
  }
}

resource "aws_iam_policy" "lambda_s3" {
  name        = "${var.resource_prefix}-lambda-s3-policy"
  description = "S3 access policy for Lambda scraper function"
  policy      = data.aws_iam_policy_document.lambda_s3.json

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "lambda_s3" {
  role       = aws_iam_role.lambda.name
  policy_arn = aws_iam_policy.lambda_s3.arn
}

# Attach AWS managed policy for Lambda basic execution (CloudWatch Logs)
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# VPC execution policy (if Lambda needs VPC access for internet)
resource "aws_iam_role_policy_attachment" "lambda_vpc_execution" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# ----------------------------------------------------------------------------
# Glue Service Role
# ----------------------------------------------------------------------------

# Trust policy for Glue service
data "aws_iam_policy_document" "glue_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["glue.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "glue" {
  name               = "${var.resource_prefix}-glue-role"
  assume_role_policy = data.aws_iam_policy_document.glue_assume_role.json

  tags = merge(
    var.tags,
    {
      Name = "${var.resource_prefix}-glue-role"
    }
  )
}

# Glue S3 access policy
data "aws_iam_policy_document" "glue_s3" {
  # Full access to all data buckets
  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket"
    ]
    resources = [
      var.raw_bucket_arn,
      "${var.raw_bucket_arn}/*",
      var.silver_bucket_arn,
      "${var.silver_bucket_arn}/*",
      var.gold_bucket_arn,
      "${var.gold_bucket_arn}/*",
      var.dlq_bucket_arn,
      "${var.dlq_bucket_arn}/*"
    ]
  }

  # Access to Glue script bucket
  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:ListBucket"
    ]
    resources = [
      var.glue_script_bucket_arn,
      "${var.glue_script_bucket_arn}/*"
    ]
  }
}

resource "aws_iam_policy" "glue_s3" {
  name        = "${var.resource_prefix}-glue-s3-policy"
  description = "S3 access policy for Glue ETL jobs"
  policy      = data.aws_iam_policy_document.glue_s3.json

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "glue_s3" {
  role       = aws_iam_role.glue.name
  policy_arn = aws_iam_policy.glue_s3.arn
}

# Glue Catalog access policy
data "aws_iam_policy_document" "glue_catalog" {
  statement {
    effect = "Allow"
    actions = [
      "glue:GetDatabase",
      "glue:GetTable",
      "glue:GetPartition",
      "glue:GetPartitions",
      "glue:CreateTable",
      "glue:UpdateTable",
      "glue:DeleteTable",
      "glue:CreatePartition",
      "glue:UpdatePartition",
      "glue:DeletePartition",
      "glue:BatchCreatePartition",
      "glue:BatchDeletePartition",
      "glue:GetUserDefinedFunctions"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "glue_catalog" {
  name        = "${var.resource_prefix}-glue-catalog-policy"
  description = "Glue Catalog access policy for ETL jobs"
  policy      = data.aws_iam_policy_document.glue_catalog.json

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "glue_catalog" {
  role       = aws_iam_role.glue.name
  policy_arn = aws_iam_policy.glue_catalog.arn
}

# CloudWatch Logs policy for Glue
data "aws_iam_policy_document" "glue_logs" {
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = [
      "arn:aws:logs:*:*:/aws-glue/*"
    ]
  }
}

resource "aws_iam_policy" "glue_logs" {
  name        = "${var.resource_prefix}-glue-logs-policy"
  description = "CloudWatch Logs access for Glue jobs"
  policy      = data.aws_iam_policy_document.glue_logs.json

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "glue_logs" {
  role       = aws_iam_role.glue.name
  policy_arn = aws_iam_policy.glue_logs.arn
}

# Attach AWS managed Glue service policy
resource "aws_iam_role_policy_attachment" "glue_service" {
  role       = aws_iam_role.glue.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

