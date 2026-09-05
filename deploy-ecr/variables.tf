variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name used for tagging and as the first path segment of repository names"
  type        = string
  default     = "deploy-ecr"
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

variable "repositories" {
  description = "Map of ECR repositories to create. Key = short name (e.g. app, api)."
  type = map(object({
    enabled         = optional(bool, true)
    mutable         = optional(bool, true)
    scan_on_push    = optional(bool, true)
    max_image_count = optional(number, 10)
  }))
  default = {
    app = {
      enabled         = true
      mutable         = true
      scan_on_push    = true
      max_image_count = 10
    }
  }

  validation {
    condition     = length(var.repositories) > 0
    error_message = "repositories must contain at least one entry."
  }

  validation {
    condition = alltrue([
      for k, v in var.repositories :
      v.max_image_count >= 1 && v.max_image_count <= 1000
    ])
    error_message = "Each repository max_image_count must be between 1 and 1000."
  }
}

variable "encryption_type" {
  description = "ECR encryption at rest: AES256 (SSE-S3) or KMS (AWS-managed key unless kms_key is set)"
  type        = string
  default     = "AES256"

  validation {
    condition     = contains(["AES256", "KMS"], var.encryption_type)
    error_message = "encryption_type must be AES256 or KMS."
  }
}

variable "kms_key" {
  description = "Optional KMS key ARN or ID when encryption_type is KMS. Leave null to use the AWS-managed ECR key."
  type        = string
  default     = null
}

variable "untagged_expiry_days" {
  description = "Expire untagged images after this many days"
  type        = number
  default     = 7

  validation {
    condition     = var.untagged_expiry_days >= 1 && var.untagged_expiry_days <= 365
    error_message = "untagged_expiry_days must be between 1 and 365."
  }
}

variable "force_delete" {
  description = "Allow terraform destroy to delete repositories that still contain images"
  type        = bool
  default     = true
}

locals {
  repositories = {
    for name, cfg in var.repositories : name => cfg if cfg.enabled
  }
}
