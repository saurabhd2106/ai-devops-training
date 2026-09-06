output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "public_subnet_id" {
  description = "ID of the public subnet"
  value       = aws_subnet.public.id
}

output "security_group_ids" {
  description = "Security group IDs keyed by VM role"
  value       = { for name, sg in aws_security_group.instance : name => sg.id }
}

output "instance_ids" {
  description = "EC2 instance IDs keyed by VM role"
  value       = { for name, inst in aws_instance.this : name => inst.id }
}

output "private_ips" {
  description = "Private IP addresses keyed by VM role"
  value       = { for name, inst in aws_instance.this : name => inst.private_ip }
}

output "public_ips" {
  description = "Public IP addresses keyed by VM role"
  value       = { for name, inst in aws_instance.this : name => inst.public_ip }
}

output "key_pair_name" {
  description = "Name of the imported EC2 key pair"
  value       = aws_key_pair.this.key_name
}

output "ssh_commands" {
  description = "SSH commands keyed by VM role (Amazon Linux 2023 user is ec2-user)"
  value = {
    for name, inst in aws_instance.this :
    name => "ssh -i /path/to/your/private_key ec2-user@${inst.public_ip}"
  }
}

output "ssm_commands" {
  description = "SSM Session Manager commands keyed by VM role"
  value = {
    for name, inst in aws_instance.this :
    name => "aws ssm start-session --target ${inst.id} --region ${var.aws_region}"
  }
}

output "instances" {
  description = "Summary of each VM: id, IPs, and instance type"
  value = {
    for name, inst in aws_instance.this : name => {
      id            = inst.id
      public_ip     = inst.public_ip
      private_ip    = inst.private_ip
      instance_type = inst.instance_type
    }
  }
}

output "ci_artifacts_bucket" {
  description = "S3 bucket name for Jenkins CI artefacts (sample-java-app JAR and test reports)"
  value       = aws_s3_bucket.ci_artifacts.bucket
}

output "ci_artifacts_bucket_arn" {
  description = "ARN of the CI artefacts S3 bucket"
  value       = aws_s3_bucket.ci_artifacts.arn
}

output "instance_role_name" {
  description = "Shared EC2 instance IAM role name (Jenkins, SonarQube, app)"
  value       = aws_iam_role.instance.name
}

output "instance_role_arn" {
  description = "Shared EC2 instance IAM role ARN"
  value       = aws_iam_role.instance.arn
}
