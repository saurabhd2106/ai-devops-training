resource "aws_security_group" "alb" {
  name_prefix = "${local.name_prefix}-alb-"
  description = "ALB ingress from allowed CIDR; egress to Fargate tasks"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${local.name_prefix}-alb-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb.id
  description       = "HTTP from allowed CIDR"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = var.allowed_ingress_cidr

  tags = {
    Name = "${local.name_prefix}-alb-http"
  }
}

resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  count = local.enable_https ? 1 : 0

  security_group_id = aws_security_group.alb.id
  description       = "HTTPS from allowed CIDR"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = var.allowed_ingress_cidr

  tags = {
    Name = "${local.name_prefix}-alb-https"
  }
}

resource "aws_vpc_security_group_egress_rule" "alb_to_tasks" {
  for_each = local.services

  security_group_id            = aws_security_group.alb.id
  description                  = "Forward to ${each.key} tasks on container port"
  ip_protocol                  = "tcp"
  from_port                    = each.value.container_port
  to_port                      = each.value.container_port
  referenced_security_group_id = aws_security_group.task[each.key].id

  tags = {
    Name = "${local.name_prefix}-alb-to-${each.key}"
  }
}

resource "aws_security_group" "task" {
  for_each = local.services

  name_prefix = "${local.name_prefix}-${each.key}-"
  description = "Fargate tasks for ${each.key}; ingress from ALB only"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${local.name_prefix}-${each.key}-task-sg"
    Role = each.key
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "task_from_alb" {
  for_each = local.services

  security_group_id            = aws_security_group.task[each.key].id
  description                  = "Allow ALB to reach ${each.key} on container port"
  ip_protocol                  = "tcp"
  from_port                    = each.value.container_port
  to_port                      = each.value.container_port
  referenced_security_group_id = aws_security_group.alb.id

  tags = {
    Name = "${local.name_prefix}-${each.key}-from-alb"
    Role = each.key
  }
}

resource "aws_vpc_security_group_egress_rule" "task_https" {
  for_each = local.services

  security_group_id = aws_security_group.task[each.key].id
  description       = "HTTPS for ECR pulls, CloudWatch, and AWS APIs via NAT"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"

  tags = {
    Name = "${local.name_prefix}-${each.key}-egress-https"
    Role = each.key
  }
}
