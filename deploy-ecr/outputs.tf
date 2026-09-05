output "registry_id" {
  description = "AWS account ID of the ECR registry"
  value       = data.aws_caller_identity.current.account_id
}

output "repository_urls" {
  description = "ECR repository URLs keyed by short name"
  value       = { for name, repo in aws_ecr_repository.this : name => repo.repository_url }
}

output "repository_arns" {
  description = "ECR repository ARNs keyed by short name"
  value       = { for name, repo in aws_ecr_repository.this : name => repo.arn }
}

output "repository_names" {
  description = "Full ECR repository names keyed by short name"
  value       = { for name, repo in aws_ecr_repository.this : name => repo.name }
}

output "push_pull_policy_arn" {
  description = "IAM policy ARN to attach to Jenkins/CI/EC2 roles for push and pull"
  value       = aws_iam_policy.push_pull.arn
}

output "docker_login_command" {
  description = "Authenticate Docker to this ECR registry"
  value       = "aws ecr get-login-password --region ${var.aws_region} | docker login --username AWS --password-stdin ${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com"
}

output "docker_push_commands" {
  description = "Example docker tag and push commands keyed by short name"
  value = {
    for name, repo in aws_ecr_repository.this :
    name => join("\n", [
      "docker tag myapp:latest ${repo.repository_url}:latest",
      "docker push ${repo.repository_url}:latest",
    ])
  }
}
