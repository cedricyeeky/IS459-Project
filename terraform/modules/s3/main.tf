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
# S3 Event Notifications for DLQ Bucket
# ----------------------------------------------------------------------------

resource "aws_s3_bucket_notification" "dlq_notifications" {
  bucket = aws_s3_bucket.dlq.id

  topic {
    topic_arn = var.dlq_sns_topic_arn
    events    = ["s3:ObjectCreated:*"]
    
    filter_prefix = "scraping_errors/"
  }

  topic {
    topic_arn = var.dlq_sns_topic_arn
    events    = ["s3:ObjectCreated:*"]
    
    filter_prefix = "cleaning_errors/"
  }

  topic {
    topic_arn = var.dlq_sns_topic_arn
    events    = ["s3:ObjectCreated:*"]
    
    filter_prefix = "feature_eng_errors/"
  }

  depends_on = [aws_s3_bucket.dlq]
}

