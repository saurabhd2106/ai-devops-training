data "aws_iam_policy_document" "push_pull" {
  statement {
    sid    = "ECRGetAuthorizationToken"
    effect = "Allow"
    actions = [
      "ecr:GetAuthorizationToken",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "ECRPushPull"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "ecr:DescribeRepositories",
      "ecr:DescribeImages",
      "ecr:ListImages",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage",
    ]
    resources = [for repo in aws_ecr_repository.this : repo.arn]
  }
}

resource "aws_iam_policy" "push_pull" {
  name        = "${var.project_name}-ecr-push-pull-${var.environment}"
  description = "Push and pull images for ${var.project_name} ECR repositories"
  policy      = data.aws_iam_policy_document.push_pull.json

  tags = {
    Name = "${var.project_name}-ecr-push-pull-${var.environment}"
  }
}
