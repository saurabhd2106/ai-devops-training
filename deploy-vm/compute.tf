data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

resource "aws_key_pair" "this" {
  key_name   = "${var.key_name}-${var.environment}"
  public_key = trimspace(var.ssh_public_key)

  tags = {
    Name = "${var.key_name}-${var.environment}"
  }
}

resource "aws_instance" "this" {
  for_each = local.vms

  ami                         = data.aws_ssm_parameter.al2023.value
  instance_type               = each.value.instance_type
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.instance[each.key].id]
  key_name                    = aws_key_pair.this.key_name
  iam_instance_profile        = aws_iam_instance_profile.instance.name
  associate_public_ip_address = true
  ebs_optimized               = true
  monitoring                  = var.enable_detailed_monitoring

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "enabled"
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = each.value.root_volume_size
    encrypted             = true
    delete_on_termination = true
  }

  volume_tags = {
    Name        = "${var.project_name}-${var.environment}-${each.key}"
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
    Role        = each.key
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-${each.key}"
    Role = each.key
  }

  lifecycle {
    ignore_changes = [ami]
  }
}
