# ============================================================================
# S3 Module - Outputs
# ============================================================================

# Raw Bucket
output "raw_bucket_name" {
  description = "Name of the raw data S3 bucket"
  value       = aws_s3_bucket.raw.id
}

output "raw_bucket_arn" {
  description = "ARN of the raw data S3 bucket"
  value       = aws_s3_bucket.raw.arn
}

# Silver Bucket
output "silver_bucket_name" {
  description = "Name of the silver data S3 bucket"
  value       = aws_s3_bucket.silver.id
}

output "silver_bucket_arn" {
  description = "ARN of the silver data S3 bucket"
  value       = aws_s3_bucket.silver.arn
}

# Gold Bucket
output "gold_bucket_name" {
  description = "Name of the gold data S3 bucket"
  value       = aws_s3_bucket.gold.id
}

output "gold_bucket_arn" {
  description = "ARN of the gold data S3 bucket"
  value       = aws_s3_bucket.gold.arn
}

# DLQ Bucket
output "dlq_bucket_name" {
  description = "Name of the DLQ S3 bucket"
  value       = aws_s3_bucket.dlq.id
}

output "dlq_bucket_arn" {
  description = "ARN of the DLQ S3 bucket"
  value       = aws_s3_bucket.dlq.arn
}

