data "aws_iam_policy_document" "bedrock_logging_assume" {
  count = var.enable_invocation_logging ? 1 : 0

  statement {
    sid     = "BedrockAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["bedrock.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:bedrock:${var.aws_region}:${data.aws_caller_identity.current.account_id}:*"]
    }
  }
}

data "aws_iam_policy_document" "bedrock_logging" {
  count = var.enable_invocation_logging ? 1 : 0

  statement {
    sid    = "CloudWatchLogsDelivery"
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = ["${aws_cloudwatch_log_group.bedrock[0].arn}:*"]
  }
}

resource "aws_cloudwatch_log_group" "bedrock" {
  count = var.enable_invocation_logging ? 1 : 0

  name              = "/aws/bedrock/${var.project_name}-${var.environment}"
  retention_in_days = var.log_retention_days

  tags = {
    Name = "${var.project_name}-invocation-logs-${var.environment}"
  }
}

resource "aws_iam_role" "bedrock_logging" {
  count = var.enable_invocation_logging ? 1 : 0

  name               = "${var.project_name}-logging-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.bedrock_logging_assume[0].json

  tags = {
    Name = "${var.project_name}-logging-${var.environment}"
  }
}

resource "aws_iam_role_policy" "bedrock_logging" {
  count = var.enable_invocation_logging ? 1 : 0

  name   = "${var.project_name}-logging-${var.environment}"
  role   = aws_iam_role.bedrock_logging[0].id
  policy = data.aws_iam_policy_document.bedrock_logging[0].json
}

# Regional singleton: only one Bedrock invocation logging config exists per region.
# Do not define this resource in another Terraform root for the same region.
resource "aws_bedrock_model_invocation_logging_configuration" "this" {
  count = var.enable_invocation_logging ? 1 : 0

  logging_config {
    embedding_data_delivery_enabled = true
    image_data_delivery_enabled     = true
    text_data_delivery_enabled      = true
    video_data_delivery_enabled     = true

    cloudwatch_config {
      log_group_name = aws_cloudwatch_log_group.bedrock[0].name
      role_arn       = aws_iam_role.bedrock_logging[0].arn
    }
  }

  depends_on = [
    aws_iam_role_policy.bedrock_logging,
  ]
}
