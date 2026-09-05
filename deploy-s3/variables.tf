variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name used for tagging and as a prefix for the default bucket name"
  type        = string
  default     = "deploy-s3"
}

variable "environment" {
  description = "Environment name (development, staging, production, testing)"
  type        = string
  default     = "development"

  validation {
    condition     = contains(["development", "staging", "production", "testing"], var.environment)
    error_message = "environment must be one of: development, staging, production, testing."
  }
}

variable "bucket_name" {
  description = "Optional explicit S3 bucket name. Leave null to use {project_name}-{environment}-{account_id}."
  type        = string
  default     = null

  validation {
    condition = var.bucket_name == null || (
      can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.bucket_name)) &&
      !can(regex("\\.\\.", var.bucket_name)) &&
      !can(regex("^\\d+\\.\\d+\\.\\d+\\.\\d+$", var.bucket_name))
    )
    error_message = "bucket_name must be 3–63 chars, lowercase letters/numbers/dots/hyphens, start and end with a letter or number, no consecutive dots, and not an IP address."
  }
}

variable "enable_versioning" {
  description = "Enable S3 bucket versioning"
  type        = bool
  default     = true
}

variable "encryption_type" {
  description = "S3 encryption at rest: AES256 (SSE-S3) or KMS (SSE-KMS)"
  type        = string
  default     = "AES256"

  validation {
    condition     = contains(["AES256", "KMS"], var.encryption_type)
    error_message = "encryption_type must be AES256 or KMS."
  }
}

variable "kms_key" {
  description = "Optional KMS key ARN or ID when encryption_type is KMS. Leave null to use the AWS-managed S3 key (aws/s3)."
  type        = string
  default     = null
}

variable "force_destroy" {
  description = "Allow terraform destroy to delete the bucket even if it still contains objects"
  type        = bool
  default     = true
}

variable "abort_incomplete_multipart_days" {
  description = "Abort incomplete multipart uploads after this many days"
  type        = number
  default     = 7

  validation {
    condition     = var.abort_incomplete_multipart_days >= 1 && var.abort_incomplete_multipart_days <= 365
    error_message = "abort_incomplete_multipart_days must be between 1 and 365."
  }
}

locals {
  bucket_name = coalesce(
    var.bucket_name,
    "${var.project_name}-${var.environment}-${data.aws_caller_identity.current.account_id}"
  )
}
