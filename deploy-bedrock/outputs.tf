output "account_id" {
  description = "AWS account ID"
  value       = data.aws_caller_identity.current.account_id
}

output "invoke_policy_arn" {
  description = "IAM policy ARN to attach to callers (EC2/ECS/Lambda/user) for Bedrock invoke"
  value       = aws_iam_policy.invoke.arn
}

output "foundation_model_arns" {
  description = "Foundation model ARNs keyed by short name"
  value = {
    for name, cfg in var.models :
    name => "arn:aws:bedrock:${var.aws_region}::foundation-model/${cfg.model_id}"
  }
}

output "inference_profile_arns" {
  description = "Inference profile ARNs keyed by short name (only entries with inference_profile set)"
  value = {
    for name, cfg in var.models :
    name => "arn:aws:bedrock:${var.aws_region}::inference-profile/${cfg.inference_profile}"
    if cfg.inference_profile != null
  }
}

output "model_agreements" {
  description = "Model IDs that accepted a foundation model agreement"
  value       = { for name, r in aws_bedrock_foundation_model_agreement.this : name => r.model_id }
}

output "guardrail_arn" {
  description = "ARN of the optional Bedrock Guardrail (null if disabled)"
  value       = try(aws_bedrock_guardrail.this[0].guardrail_arn, null)
}

output "guardrail_id" {
  description = "ID of the optional Bedrock Guardrail (null if disabled)"
  value       = try(aws_bedrock_guardrail.this[0].guardrail_id, null)
}

output "invocation_log_group_name" {
  description = "CloudWatch Logs group for Bedrock invocation logging (null if disabled)"
  value       = try(aws_cloudwatch_log_group.bedrock[0].name, null)
}

output "example_converse_command" {
  description = "Example AWS CLI Converse call using the default nova_lite inference profile (adjust model id as needed)"
  value       = <<-EOT
    aws bedrock-runtime converse \
      --region ${var.aws_region} \
      --model-id ${try(var.models["nova_lite"].inference_profile, var.models[keys(var.models)[0]].model_id)} \
      --messages '[{"role":"user","content":[{"text":"Hello from deploy-bedrock"}]}]'
  EOT
}
