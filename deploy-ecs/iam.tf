data "aws_iam_policy_document" "ecs_tasks_assume" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

# Execution role: ECR pull + CloudWatch Logs (ECS agent)
resource "aws_iam_role" "execution" {
  name_prefix        = "${local.name_prefix}-exec-"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
  description        = "ECS task execution role for ${local.name_prefix}"

  tags = {
    Name = "${local.name_prefix}-execution-role"
  }
}

resource "aws_iam_role_policy_attachment" "execution_ecs" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Task role: ECS Exec (ssmmessages) for interactive debugging
data "aws_iam_policy_document" "task_ecs_exec" {
  statement {
    sid    = "ECSExec"
    effect = "Allow"
    actions = [
      "ssmmessages:CreateControlChannel",
      "ssmmessages:CreateDataChannel",
      "ssmmessages:OpenControlChannel",
      "ssmmessages:OpenDataChannel",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role" "task" {
  name_prefix        = "${local.name_prefix}-task-"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
  description        = "ECS task role for ${local.name_prefix} (ECS Exec)"

  tags = {
    Name = "${local.name_prefix}-task-role"
  }
}

resource "aws_iam_role_policy" "task_ecs_exec" {
  name_prefix = "${local.name_prefix}-exec-"
  role        = aws_iam_role.task.id
  policy      = data.aws_iam_policy_document.task_ecs_exec.json
}
