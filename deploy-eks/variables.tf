variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name used for tagging and resource name prefixes"
  type        = string
  default     = "deploy-eks"
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

variable "vpc_cidr" {
  description = "CIDR block for the VPC (kept distinct from deploy-vm 10.0.0.0/16)"
  type        = string
  default     = "10.20.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets (one per AZ; must be length 2)"
  type        = list(string)
  default     = ["10.20.0.0/24", "10.20.1.0/24"]

  validation {
    condition     = length(var.public_subnet_cidrs) == 2
    error_message = "public_subnet_cidrs must contain exactly 2 CIDR blocks."
  }
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets (one per AZ; must be length 2)"
  type        = list(string)
  default     = ["10.20.10.0/24", "10.20.11.0/24"]

  validation {
    condition     = length(var.private_subnet_cidrs) == 2
    error_message = "private_subnet_cidrs must contain exactly 2 CIDR blocks."
  }
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS control plane and managed node group"
  type        = string
  default     = "1.34"
}

variable "allowed_api_cidr" {
  description = "CIDR allowed to reach the EKS public API endpoint. Prefer your public IP as /32. Avoid 0.0.0.0/0."
  type        = string

  validation {
    condition     = can(cidrhost(var.allowed_api_cidr, 0))
    error_message = "allowed_api_cidr must be a valid CIDR block (e.g. 203.0.113.25/32)."
  }

  validation {
    condition     = var.allowed_api_cidr != "0.0.0.0/0"
    error_message = "allowed_api_cidr must not be 0.0.0.0/0. Restrict access to your public IP (/32) or a trusted network range."
  }
}

variable "additional_api_cidrs" {
  description = "Extra CIDRs for the EKS public API (e.g. Jenkins public IP as /32). Merged with allowed_api_cidr. 0.0.0.0/0 rejected."
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for c in var.additional_api_cidrs : can(cidrhost(c, 0)) && c != "0.0.0.0/0"
    ])
    error_message = "each additional_api_cidrs entry must be a valid CIDR and must not be 0.0.0.0/0."
  }
}

variable "ci_principal_arn" {
  description = "Optional IAM principal ARN (e.g. deploy-vm instance_role_arn) granted EKS cluster admin via access entry for Jenkins kubectl deploy"
  type        = string
  default     = null
}

variable "node_instance_types" {
  description = "EC2 instance types for the managed node group"
  type        = list(string)
  default     = ["t3.medium"]

  validation {
    condition     = length(var.node_instance_types) > 0
    error_message = "node_instance_types must contain at least one instance type."
  }
}

variable "node_desired_size" {
  description = "Desired number of worker nodes"
  type        = number
  default     = 2

  validation {
    condition     = var.node_desired_size >= 1 && var.node_desired_size <= 10
    error_message = "node_desired_size must be between 1 and 10."
  }
}

variable "node_min_size" {
  description = "Minimum number of worker nodes"
  type        = number
  default     = 1

  validation {
    condition     = var.node_min_size >= 0 && var.node_min_size <= 10
    error_message = "node_min_size must be between 0 and 10."
  }
}

variable "node_max_size" {
  description = "Maximum number of worker nodes"
  type        = number
  default     = 3

  validation {
    condition     = var.node_max_size >= 1 && var.node_max_size <= 20
    error_message = "node_max_size must be between 1 and 20."
  }
}

variable "node_disk_size" {
  description = "Root volume size in GiB for worker nodes (gp3, encrypted)"
  type        = number
  default     = 20

  validation {
    condition     = var.node_disk_size >= 20 && var.node_disk_size <= 100
    error_message = "node_disk_size must be between 20 and 100 GiB."
  }
}

variable "enable_cluster_logs" {
  description = "Enable EKS control-plane CloudWatch logs (api, audit, authenticator, controllerManager, scheduler). Extra cost."
  type        = bool
  default     = false
}

locals {
  cluster_name = "${var.project_name}-${var.environment}"

  # EKS disallows these AZ IDs for cluster subnets
  disallowed_az_ids = toset(["use1-az3", "usw1-az2", "cac1-az3"])

  public_access_cidrs = distinct(concat([var.allowed_api_cidr], var.additional_api_cidrs))

  enabled_cluster_log_types = var.enable_cluster_logs ? [
    "api",
    "audit",
    "authenticator",
    "controllerManager",
    "scheduler",
  ] : []
}
