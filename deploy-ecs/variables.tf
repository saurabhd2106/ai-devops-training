variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name used for tagging and resource name prefixes"
  type        = string
  default     = "deploy-ecs"
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
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for the two public subnets (ALB + NAT)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]

  validation {
    condition     = length(var.public_subnet_cidrs) == 2
    error_message = "public_subnet_cidrs must contain exactly two CIDR blocks (ALB requires two AZs)."
  }
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for the two private subnets (Fargate tasks)"
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24"]

  validation {
    condition     = length(var.private_subnet_cidrs) == 2
    error_message = "private_subnet_cidrs must contain exactly two CIDR blocks."
  }
}

variable "allowed_ingress_cidr" {
  description = "CIDR allowed to reach the ALB (HTTP/HTTPS). Prefer your public IP as /32. Use 0.0.0.0/0 only for a public demo."
  type        = string

  validation {
    condition     = can(cidrhost(var.allowed_ingress_cidr, 0))
    error_message = "allowed_ingress_cidr must be a valid CIDR block (e.g. 203.0.113.25/32)."
  }
}

variable "acm_certificate_arn" {
  description = "Optional ACM certificate ARN in this region. When set, ALB listens on HTTPS :443 and redirects HTTP to HTTPS."
  type        = string
  default     = ""
}

variable "enable_container_insights" {
  description = "Enable ECS Container Insights on the cluster (extra CloudWatch cost)."
  type        = bool
  default     = false
}

variable "services" {
  description = "Map of ECS Fargate services to create. Key = service name (e.g. app)."
  type = map(object({
    image             = optional(string, "public.ecr.aws/docker/library/nginx:stable")
    cpu               = optional(number, 512)
    memory            = optional(number, 1024)
    container_port    = optional(number, 80)
    desired_count     = optional(number, 1)
    path_pattern      = optional(string, "/*")
    listener_priority = optional(number, 100)
    create_ecr        = optional(bool, true)
    enabled           = optional(bool, true)
    health_check_path = optional(string, "/")
  }))
  default = {
    app = {
      image             = "public.ecr.aws/docker/library/nginx:stable"
      cpu               = 512
      memory            = 1024
      container_port    = 80
      desired_count     = 1
      path_pattern      = "/*"
      listener_priority = 100
      create_ecr        = true
      enabled           = true
      health_check_path = "/"
    }
  }

  validation {
    condition     = length(var.services) > 0
    error_message = "services must contain at least one entry."
  }

  validation {
    condition = alltrue([
      for k, v in var.services :
      contains([256, 512, 1024, 2048, 4096], v.cpu)
    ])
    error_message = "Each service cpu must be a valid Fargate value: 256, 512, 1024, 2048, or 4096."
  }

  validation {
    condition = alltrue([
      for k, v in var.services :
      v.container_port >= 1 && v.container_port <= 65535
    ])
    error_message = "Each container_port must be between 1 and 65535."
  }

  validation {
    condition = alltrue([
      for k, v in var.services :
      v.desired_count >= 0 && v.desired_count <= 10
    ])
    error_message = "Each desired_count must be between 0 and 10."
  }

  validation {
    condition = alltrue([
      for k, v in var.services :
      v.listener_priority >= 1 && v.listener_priority <= 50000
    ])
    error_message = "Each listener_priority must be between 1 and 50000."
  }
}

locals {
  services = {
    for name, cfg in var.services : name => cfg if cfg.enabled
  }

  name_prefix = "${var.project_name}-${var.environment}"

  enable_https = var.acm_certificate_arn != ""
}
