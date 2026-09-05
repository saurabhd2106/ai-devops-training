variable "aws_region" {
  description = "AWS region for all resources (Bedrock and models are region-specific)"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name used for tagging and resource name prefixes"
  type        = string
  default     = "deploy-bedrock"
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

variable "models" {
  description = <<-EOT
    Map of foundation models to allow via IAM. Key = short name.
    - model_id: Bedrock foundation model ID (e.g. amazon.nova-lite-v1:0)
    - inference_profile: optional cross-region inference profile ID (e.g. us.amazon.nova-lite-v1:0)
    - accept_agreement: create aws_bedrock_foundation_model_agreement for third-party models
  EOT
  type = map(object({
    model_id          = string
    inference_profile = optional(string)
    accept_agreement  = optional(bool, false)
  }))
  default = {
    nova_lite = {
      model_id          = "amazon.nova-lite-v1:0"
      inference_profile = "us.amazon.nova-lite-v1:0"
      accept_agreement  = false
    }
    titan_embed = {
      model_id         = "amazon.titan-embed-text-v2:0"
      accept_agreement = false
    }
  }

  validation {
    condition     = length(var.models) > 0
    error_message = "models must contain at least one entry."
  }
}

variable "enable_invocation_logging" {
  description = "Configure Bedrock model invocation logging to CloudWatch Logs (regional singleton)"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention in days for Bedrock invocation logs"
  type        = number
  default     = 14

  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653
    ], var.log_retention_days)
    error_message = "log_retention_days must be a valid CloudWatch Logs retention value."
  }
}

variable "enable_guardrail" {
  description = "Create an Amazon Bedrock Guardrail with content and profanity filters"
  type        = bool
  default     = false
}

variable "guardrail_name" {
  description = "Name for the optional Bedrock Guardrail"
  type        = string
  default     = "deploy-bedrock-guardrail"
}

variable "enable_anthropic_use_case" {
  description = "Submit Anthropic first-time use-case form via aws_bedrock_use_case_for_model_access (destroy does not delete it)"
  type        = bool
  default     = false
}

variable "anthropic_use_case_form" {
  description = "JSON object for Anthropic use-case form when enable_anthropic_use_case is true"
  type = object({
    companyName         = string
    companyWebsite      = string
    intendedUsers       = string
    industryOption      = string
    otherIndustryOption = optional(string, "")
    useCases            = string
  })
  default = {
    companyName         = "Example Corp"
    companyWebsite      = "https://example.com"
    intendedUsers       = "0"
    industryOption      = "Technology"
    otherIndustryOption = ""
    useCases            = "- Internal developer assistants\n- Document summarization\n- Code generation and review"
  }
}

locals {
  models_with_agreement = {
    for name, cfg in var.models : name => cfg if cfg.accept_agreement
  }

  # Use * region for foundation models when an inference profile is set so
  # cross-region (geo) routing can invoke the model in destination Regions.
  foundation_model_arns = [
    for name, cfg in var.models :
    cfg.inference_profile != null
    ? "arn:aws:bedrock:*::foundation-model/${cfg.model_id}"
    : "arn:aws:bedrock:${var.aws_region}::foundation-model/${cfg.model_id}"
  ]

  inference_profile_arns = compact([
    for name, cfg in var.models :
    cfg.inference_profile != null ? "arn:aws:bedrock:${var.aws_region}:${data.aws_caller_identity.current.account_id}:inference-profile/${cfg.inference_profile}" : null
  ])

  # System-defined inference profile ARNs (no account id) are also accepted by Invoke/Converse.
  inference_profile_arns_system = compact([
    for name, cfg in var.models :
    cfg.inference_profile != null ? "arn:aws:bedrock:${var.aws_region}::inference-profile/${cfg.inference_profile}" : null
  ])

  invoke_resource_arns = concat(
    local.foundation_model_arns,
    local.inference_profile_arns,
    local.inference_profile_arns_system,
  )
}
