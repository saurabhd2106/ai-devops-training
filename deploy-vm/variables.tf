variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name used for tagging and resource name prefixes"
  type        = string
  default     = "deploy-vm"
}

variable "environment" {
  description = "Environment name (development, staging, production)"
  type        = string
  default     = "development"

  validation {
    condition     = contains(["development", "staging", "production", "testing"], var.environment)
    error_message = "environment must be one of: development, staging, production, testing."
  }
}

variable "vms" {
  description = "Map of VMs to create. Key = role name (e.g. app, sonarqube, jenkins)."
  type = map(object({
    instance_type    = string
    root_volume_size = optional(number, 20)
    ingress_ports    = optional(list(number), [])
    enabled          = optional(bool, true)
  }))
  default = {
    app = {
      instance_type    = "t3.small"
      root_volume_size = 30
      ingress_ports    = [80, 443]
    }
    sonarqube = {
      instance_type    = "t3.medium"
      root_volume_size = 50
      ingress_ports    = [9000]
    }
    jenkins = {
      instance_type    = "t3.medium"
      root_volume_size = 40
      ingress_ports    = [8080]
    }
  }

  validation {
    condition = alltrue([
      for k, v in var.vms :
      v.root_volume_size >= 8 && v.root_volume_size <= 100
    ])
    error_message = "Each VM root_volume_size must be between 8 and 100 GiB."
  }

  validation {
    condition = alltrue(flatten([
      for k, v in var.vms : [
        for port in v.ingress_ports : port >= 1 && port <= 65535
      ]
    ]))
    error_message = "Each ingress_ports entry must be between 1 and 65535."
  }

  validation {
    condition     = length(var.vms) > 0
    error_message = "vms must contain at least one entry."
  }
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block for the public subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "allowed_ssh_cidr" {
  description = "CIDR allowed for SSH and role UI/app ports. Prefer your public IP as /32. Avoid 0.0.0.0/0."
  type        = string

  validation {
    condition     = can(cidrhost(var.allowed_ssh_cidr, 0))
    error_message = "allowed_ssh_cidr must be a valid CIDR block (e.g. 203.0.113.25/32)."
  }

  validation {
    condition     = var.allowed_ssh_cidr != "0.0.0.0/0"
    error_message = "allowed_ssh_cidr must not be 0.0.0.0/0. Restrict access to your public IP (/32) or a trusted network range."
  }
}

variable "ssh_public_key" {
  description = "SSH public key material to import as an EC2 key pair (e.g. contents of ~/.ssh/id_ed25519.pub). Private key is never stored in Terraform."
  type        = string
  sensitive   = true

  validation {
    condition     = length(trimspace(var.ssh_public_key)) > 0 && can(regex("^(ssh-(rsa|ed25519)|ecdsa-sha2-nistp(256|384|521)) ", trimspace(var.ssh_public_key)))
    error_message = "ssh_public_key must be a non-empty OpenSSH public key (ssh-rsa, ssh-ed25519, or ecdsa-sha2-nistp*)."
  }
}

variable "key_name" {
  description = "Name for the imported EC2 key pair"
  type        = string
  default     = "deploy-vm-key"
}

variable "enable_detailed_monitoring" {
  description = "Enable EC2 detailed (1-minute) CloudWatch monitoring. Extra cost."
  type        = bool
  default     = false
}

locals {
  vms = {
    for name, cfg in var.vms : name => cfg if cfg.enabled
  }

  # Flatten role ingress ports for security group rules: "app-80" => { vm, port }
  vm_ingress_ports = {
    for pair in flatten([
      for vm_name, cfg in local.vms : [
        for port in cfg.ingress_ports : {
          key  = "${vm_name}-${port}"
          name = vm_name
          port = port
        }
      ]
    ]) : pair.key => pair
  }
}
