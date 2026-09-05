data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "invoke" {
  statement {
    sid    = "BedrockInvokeModels"
    effect = "Allow"
    actions = [
      "bedrock:InvokeModel",
      "bedrock:InvokeModelWithResponseStream",
      "bedrock:Converse",
      "bedrock:ConverseStream",
    ]
    resources = local.invoke_resource_arns
  }

  dynamic "statement" {
    for_each = var.enable_guardrail ? [1] : []
    content {
      sid    = "BedrockApplyGuardrail"
      effect = "Allow"
      actions = [
        "bedrock:ApplyGuardrail",
      ]
      resources = [aws_bedrock_guardrail.this[0].guardrail_arn]
    }
  }

  statement {
    sid    = "BedrockListFoundationModels"
    effect = "Allow"
    actions = [
      "bedrock:ListFoundationModels",
      "bedrock:GetFoundationModel",
      "bedrock:ListInferenceProfiles",
      "bedrock:GetInferenceProfile",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "invoke" {
  name        = "${var.project_name}-invoke-${var.environment}"
  description = "Invoke selected Amazon Bedrock foundation models for ${var.project_name}"
  policy      = data.aws_iam_policy_document.invoke.json

  tags = {
    Name = "${var.project_name}-invoke-${var.environment}"
  }
}
