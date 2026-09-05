locals {
  ecr_services = {
    for name, cfg in local.services : name => cfg if cfg.create_ecr
  }
}

resource "aws_ecr_repository" "service" {
  for_each = local.ecr_services

  name                 = "${local.name_prefix}-${each.key}"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = {
    Name = "${local.name_prefix}-${each.key}"
    Role = each.key
  }
}

resource "aws_ecr_lifecycle_policy" "service" {
  for_each = local.ecr_services

  repository = aws_ecr_repository.service[each.key].name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 10 images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}
