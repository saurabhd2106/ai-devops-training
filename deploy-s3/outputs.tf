output "bucket_id" {
  description = "S3 bucket name (id)"
  value       = aws_s3_bucket.this.id
}

output "bucket_arn" {
  description = "S3 bucket ARN"
  value       = aws_s3_bucket.this.arn
}

output "bucket_region" {
  description = "AWS region of the S3 bucket"
  value       = aws_s3_bucket.this.region
}

output "bucket_domain_name" {
  description = "S3 bucket regional domain name"
  value       = aws_s3_bucket.this.bucket_regional_domain_name
}

output "account_id" {
  description = "AWS account ID that owns the bucket"
  value       = data.aws_caller_identity.current.account_id
}
