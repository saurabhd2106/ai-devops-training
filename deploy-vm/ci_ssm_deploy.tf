# Allow Jenkins (shared instance role) to discover the app EC2 and deploy via SSM.

data "aws_iam_policy_document" "ci_ssm_deploy" {
  statement {
    sid    = "DescribeInstancesForAppDiscovery"
    effect = "Allow"
    actions = [
      "ec2:DescribeInstances",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "SendCommandToAppInstances"
    effect = "Allow"
    actions = [
      "ssm:SendCommand",
    ]
    resources = [
      "arn:aws:ssm:${var.aws_region}::document/AWS-RunShellScript",
      "arn:aws:ec2:${var.aws_region}:${data.aws_caller_identity.current.account_id}:instance/*",
    ]
  }

  statement {
    sid    = "GetCommandInvocationResults"
    effect = "Allow"
    actions = [
      "ssm:GetCommandInvocation",
      "ssm:ListCommands",
      "ssm:ListCommandInvocations",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "ci_ssm_deploy" {
  name   = "${var.project_name}-${var.environment}-ci-ssm-deploy"
  role   = aws_iam_role.instance.id
  policy = data.aws_iam_policy_document.ci_ssm_deploy.json
}
