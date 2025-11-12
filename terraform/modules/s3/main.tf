# ============================================================================
# S3 Module - Storage Layer for Flight Delays Pipeline
# ============================================================================
# Creates 4 S3 buckets: Raw, Silver, Gold, and DLQ
# Implements lifecycle policies, versioning, encryption, and event notifications

# ----------------------------------------------------------------------------
# Raw Data Bucket
# ----------------------------------------------------------------------------

resource "aws_s3_bucket" "raw" {
  bucket = "${var.resource_prefix}-raw"

  tags = merge(
    var.tags,
    {
      Name  = "${var.resource_prefix}-raw"
      Layer = "raw"
    }
  )
}

# Versioning disabled to simplify cleanup
# Note: If versioning was previously enabled, suspending it doesn't delete existing versions
# resource "aws_s3_bucket_versioning" "raw" {
#   bucket = aws_s3_bucket.raw.id
#
#   versioning_configuration {
#     status = "Suspended"  # Changed from "Enabled" to "Suspended"
#   }
# }

resource "aws_s3_bucket_server_side_encryption_configuration" "raw" {
  bucket = aws_s3_bucket.raw.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "raw" {
  bucket = aws_s3_bucket.raw.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "raw" {
  bucket = aws_s3_bucket.raw.id

  rule {
    id     = "transition-to-ia"
    status = "Enabled"

    filter {}

    transition {
      days          = var.raw_lifecycle_days
      storage_class = "STANDARD_IA"
    }
  }
}

# Create folder structure for raw bucket
resource "aws_s3_object" "raw_folders" {
  for_each = toset([
    "historical/",
    "supplemental/",
    "scraped/"
  ])

  bucket       = aws_s3_bucket.raw.id
  key          = each.value
  content_type = "application/x-directory"
}

# ----------------------------------------------------------------------------
# QuickSight Access Policy for Raw Bucket (Athena Query Results)
# ----------------------------------------------------------------------------

# Get AWS account ID for QuickSight service role ARN
data "aws_caller_identity" "current" {}

# Policy document to allow QuickSight service role to write Athena query results
data "aws_iam_policy_document" "raw_quicksight" {
  statement {
    sid    = "AllowQuickSightAthenaWrites"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = [
        "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/service-role/aws-quicksight-service-role-v0"
      ]
    }

    actions = [
      "s3:GetBucketLocation",
      "s3:ListBucket",
      "s3:GetObject",
      "s3:GetObjectVersion",
      "s3:AbortMultipartUpload",
      "s3:PutObject"
    ]

    resources = [
      aws_s3_bucket.raw.arn,
      "${aws_s3_bucket.raw.arn}/*"
    ]
  }
}

# Attach the policy to the raw bucket
resource "aws_s3_bucket_policy" "raw_quicksight" {
  bucket = aws_s3_bucket.raw.id
  policy = data.aws_iam_policy_document.raw_quicksight.json

  depends_on = [aws_s3_bucket.raw]
}

# ----------------------------------------------------------------------------
# Silver Data Bucket
# ----------------------------------------------------------------------------

resource "aws_s3_bucket" "silver" {
  bucket = "${var.resource_prefix}-silver"

  tags = merge(
    var.tags,
    {
      Name  = "${var.resource_prefix}-silver"
      Layer = "silver"
    }
  )
}

resource "aws_s3_bucket_server_side_encryption_configuration" "silver" {
  bucket = aws_s3_bucket.silver.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "silver" {
  bucket = aws_s3_bucket.silver.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "silver" {
  bucket = aws_s3_bucket.silver.id

  rule {
    id     = "transition-to-ia"
    status = "Enabled"

    filter {}

    transition {
      days          = var.silver_lifecycle_days
      storage_class = "STANDARD_IA"
    }
  }
}

# ----------------------------------------------------------------------------
# QuickSight Access Policy for Silver Bucket (Data Read Access)
# ----------------------------------------------------------------------------

# Policy document to allow QuickSight service role to read data from silver bucket
data "aws_iam_policy_document" "silver_quicksight" {
  statement {
    sid    = "AllowQuickSightDataRead"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = [
        "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/service-role/aws-quicksight-service-role-v0"
      ]
    }

    actions = [
      "s3:GetBucketLocation",
      "s3:ListBucket",
      "s3:GetObject",
      "s3:GetObjectVersion"
    ]

    resources = [
      aws_s3_bucket.silver.arn,
      "${aws_s3_bucket.silver.arn}/*"
    ]
  }
}

# Attach the policy to the silver bucket
resource "aws_s3_bucket_policy" "silver_quicksight" {
  bucket = aws_s3_bucket.silver.id
  policy = data.aws_iam_policy_document.silver_quicksight.json

  depends_on = [aws_s3_bucket.silver]
}

# ----------------------------------------------------------------------------
# Gold Data Bucket
# ----------------------------------------------------------------------------

resource "aws_s3_bucket" "gold" {
  bucket = "${var.resource_prefix}-gold"

  tags = merge(
    var.tags,
    {
      Name  = "${var.resource_prefix}-gold"
      Layer = "gold"
    }
  )
}

resource "aws_s3_bucket_server_side_encryption_configuration" "gold" {
  bucket = aws_s3_bucket.gold.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "gold" {
  bucket = aws_s3_bucket.gold.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "gold" {
  bucket = aws_s3_bucket.gold.id

  rule {
    id     = "transition-to-ia"
    status = "Enabled"

    filter {}

    transition {
      days          = var.gold_lifecycle_days
      storage_class = "STANDARD_IA"
    }
  }
}

# ----------------------------------------------------------------------------
# QuickSight Access Policy for Gold Bucket (Data Read Access)
# ----------------------------------------------------------------------------

# Policy document to allow QuickSight service role to read data from gold bucket
data "aws_iam_policy_document" "gold_quicksight" {
  statement {
    sid    = "AllowQuickSightDataRead"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = [
        "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/service-role/aws-quicksight-service-role-v0"
      ]
    }

    actions = [
      "s3:GetBucketLocation",
      "s3:ListBucket",
      "s3:GetObject",
      "s3:GetObjectVersion"
    ]

    resources = [
      aws_s3_bucket.gold.arn,
      "${aws_s3_bucket.gold.arn}/*"
    ]
  }
}

# Attach the policy to the gold bucket
resource "aws_s3_bucket_policy" "gold_quicksight" {
  bucket = aws_s3_bucket.gold.id
  policy = data.aws_iam_policy_document.gold_quicksight.json

  depends_on = [aws_s3_bucket.gold]
}

# ----------------------------------------------------------------------------
# Dead Letter Queue (DLQ) Bucket
# ----------------------------------------------------------------------------

resource "aws_s3_bucket" "dlq" {
  bucket = "${var.resource_prefix}-dlq"

  tags = merge(
    var.tags,
    {
      Name  = "${var.resource_prefix}-dlq"
      Layer = "dlq"
    }
  )
}

resource "aws_s3_bucket_server_side_encryption_configuration" "dlq" {
  bucket = aws_s3_bucket.dlq.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "dlq" {
  bucket = aws_s3_bucket.dlq.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "dlq" {
  bucket = aws_s3_bucket.dlq.id

  rule {
    id     = "expire-errors"
    status = "Enabled"

    filter {}

    expiration {
      days = var.dlq_expiration_days
    }
  }
}

# Create folder structure for DLQ bucket
resource "aws_s3_object" "dlq_folders" {
  for_each = toset([
    "scraping_errors/",
    "cleaning_errors/",
    "feature_eng_errors/"
  ])

  bucket       = aws_s3_bucket.dlq.id
  key          = each.value
  content_type = "application/x-directory"
}

# ----------------------------------------------------------------------------
# S3 EventBridge Notifications for Raw Bucket
# ----------------------------------------------------------------------------

# Enable EventBridge notifications for Raw bucket (for scraped data processing)
resource "aws_s3_bucket_notification" "raw_eventbridge" {
  bucket      = aws_s3_bucket.raw.id
  eventbridge = true
}

# ----------------------------------------------------------------------------
# S3 Event Notifications for DLQ Bucket
# ----------------------------------------------------------------------------

# NOTE: S3 → SNS direct notifications replaced with S3 → Lambda → SNS
# The direct SNS notifications were not working reliably.
# Now handled by lambda_dlq_notifier module instead.

# resource "aws_s3_bucket_notification" "dlq_notifications" {
#   bucket = aws_s3_bucket.dlq.id
#
#   topic {
#     topic_arn = var.dlq_sns_topic_arn
#     events    = ["s3:ObjectCreated:*"]
#     
#     filter_prefix = "scraping_errors/"
#   }
#
#   topic {
#     topic_arn = var.dlq_sns_topic_arn
#     events    = ["s3:ObjectCreated:*"]
#     
#     filter_prefix = "cleaning_errors/"
#   }
#
#   topic {
#     topic_arn = var.dlq_sns_topic_arn
#     events    = ["s3:ObjectCreated:*"]
#     
#     filter_prefix = "feature_eng_errors/"
#   }
#
#   depends_on = [aws_s3_bucket.dlq]
# }


