output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "IDs of the public subnets (ALB + NAT)"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets (Fargate tasks)"
  value       = aws_subnet.private[*].id
}

output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = aws_lb.main.dns_name
}

output "alb_url" {
  description = "HTTP(S) URL for the ALB (use from allowed_ingress_cidr)"
  value       = local.enable_https ? "https://${aws_lb.main.dns_name}" : "http://${aws_lb.main.dns_name}"
}

output "alb_arn" {
  description = "ARN of the Application Load Balancer"
  value       = aws_lb.main.arn
}

output "ecs_cluster_name" {
  description = "Name of the ECS cluster"
  value       = aws_ecs_cluster.main.name
}

output "ecs_cluster_arn" {
  description = "ARN of the ECS cluster"
  value       = aws_ecs_cluster.main.arn
}

output "service_names" {
  description = "ECS service names keyed by service map key"
  value       = { for name, svc in aws_ecs_service.service : name => svc.name }
}

output "service_arns" {
  description = "ECS service ARNs keyed by service map key"
  value       = { for name, svc in aws_ecs_service.service : name => svc.id }
}

output "ecr_repository_urls" {
  description = "ECR repository URLs for services with create_ecr = true"
  value       = { for name, repo in aws_ecr_repository.service : name => repo.repository_url }
}

output "task_definition_arns" {
  description = "Current task definition ARNs keyed by service"
  value       = { for name, td in aws_ecs_task_definition.service : name => td.arn }
}

output "cloudwatch_log_groups" {
  description = "CloudWatch log group names keyed by service"
  value       = { for name, lg in aws_cloudwatch_log_group.service : name => lg.name }
}

output "ecs_exec_commands" {
  description = "Example ECS Exec commands (replace TASK_ID after listing running tasks)"
  value = {
    for name, svc in aws_ecs_service.service :
    name => "aws ecs execute-command --cluster ${aws_ecs_cluster.main.name} --task TASK_ID --container ${name} --interactive --command /bin/sh --region ${var.aws_region}"
  }
}

output "list_tasks_commands" {
  description = "Commands to list running task IDs per service"
  value = {
    for name, svc in aws_ecs_service.service :
    name => "aws ecs list-tasks --cluster ${aws_ecs_cluster.main.name} --service-name ${svc.name} --region ${var.aws_region} --query 'taskArns' --output text"
  }
}
