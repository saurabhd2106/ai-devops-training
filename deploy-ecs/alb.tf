resource "aws_lb" "main" {
  name               = substr("${local.name_prefix}-alb", 0, 32)
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  enable_deletion_protection = false

  tags = {
    Name = "${local.name_prefix}-alb"
  }
}

resource "aws_lb_target_group" "service" {
  for_each = local.services

  name        = substr("${local.name_prefix}-${each.key}", 0, 32)
  port        = each.value.container_port
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    path                = each.value.health_check_path
    matcher             = "200-399"
    protocol            = "HTTP"
  }

  tags = {
    Name = "${local.name_prefix}-${each.key}-tg"
    Role = each.key
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Default action: forward to the service with path_pattern "/*", else first service
locals {
  default_service_name = coalesce(
    try([for k, v in local.services : k if v.path_pattern == "/*"][0], null),
    keys(local.services)[0]
  )
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  dynamic "default_action" {
    for_each = local.enable_https ? [1] : []
    content {
      type = "redirect"
      redirect {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }
  }

  dynamic "default_action" {
    for_each = local.enable_https ? [] : [1]
    content {
      type             = "forward"
      target_group_arn = aws_lb_target_group.service[local.default_service_name].arn
    }
  }
}

resource "aws_lb_listener" "https" {
  count = local.enable_https ? 1 : 0

  load_balancer_arn = aws_lb.main.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.acm_certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.service[local.default_service_name].arn
  }
}

resource "aws_lb_listener_rule" "http_path" {
  for_each = local.enable_https ? {} : {
    for name, cfg in local.services : name => cfg
    if name != local.default_service_name
  }

  listener_arn = aws_lb_listener.http.arn
  priority     = each.value.listener_priority

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.service[each.key].arn
  }

  condition {
    path_pattern {
      values = [each.value.path_pattern]
    }
  }
}

resource "aws_lb_listener_rule" "https_path" {
  for_each = local.enable_https ? {
    for name, cfg in local.services : name => cfg
    if name != local.default_service_name
  } : {}

  listener_arn = aws_lb_listener.https[0].arn
  priority     = each.value.listener_priority

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.service[each.key].arn
  }

  condition {
    path_pattern {
      values = [each.value.path_pattern]
    }
  }
}
