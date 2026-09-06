output "cluster_name" {
  description = "Name of the EKS cluster"
  value       = aws_eks_cluster.main.name
}

output "cluster_arn" {
  description = "ARN of the EKS cluster"
  value       = aws_eks_cluster.main.arn
}

output "cluster_endpoint" {
  description = "Endpoint URL for the EKS Kubernetes API server"
  value       = aws_eks_cluster.main.endpoint
}

output "cluster_version" {
  description = "Kubernetes version of the EKS cluster"
  value       = aws_eks_cluster.main.version
}

output "cluster_certificate_authority_data" {
  description = "Base64-encoded certificate data required to communicate with the cluster"
  value       = aws_eks_cluster.main.certificate_authority[0].data
  sensitive   = true
}

output "cluster_security_group_id" {
  description = "Security group ID attached to the EKS cluster control plane"
  value       = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
}

output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = aws_subnet.private[*].id
}

output "node_group_status" {
  description = "Status of the managed node group"
  value       = aws_eks_node_group.main.status
}

output "node_group_arn" {
  description = "ARN of the managed node group"
  value       = aws_eks_node_group.main.arn
}

output "kubeconfig_command" {
  description = "Configure kubectl for this cluster"
  value       = "aws eks update-kubeconfig --name ${aws_eks_cluster.main.name} --region ${var.aws_region}"
}

output "ci_deploy_policy_arn" {
  description = "IAM policy ARN to attach to Jenkins/CI (deploy-vm eks_deploy_policy_arn) for EKS kubectl deploy"
  value       = aws_iam_policy.ci_deploy.arn
}

output "ci_access_entry_principal_arn" {
  description = "IAM principal ARN granted EKS access entry (null when ci_principal_arn is unset)"
  value       = var.ci_principal_arn
}
