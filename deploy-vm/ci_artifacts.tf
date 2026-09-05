data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "ci_artifacts" {
  bucket = "${var.project_name}-${var.environment}-ci-artifacts-${data.aws_caller_identity.current.account_id}"

  tags = {
    Name = "${var.project_name}-${var.environment}-ci-artifacts"
  }
}

resource "aws_s3_bucket_public_access_block" "ci_artifacts" {
  bucket = aws_s3_bucket.ci_artifacts.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "ci_artifacts" {
  bucket = aws_s3_bucket.ci_artifacts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_ownership_controls" "ci_artifacts" {
  bucket = aws_s3_bucket.ci_artifacts.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

data "aws_iam_policy_document" "ci_artifacts" {
  statement {
    sid    = "ListCiArtifactsBucket"
    effect = "Allow"
    actions = [
      "s3:ListBucket",
    ]
    resources = [
      aws_s3_bucket.ci_artifacts.arn,
    ]
  }

  statement {
    sid    = "ReadWriteCiArtifactsObjects"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
    ]
    resources = [
      "${aws_s3_bucket.ci_artifacts.arn}/*",
    ]
  }
}

resource "aws_iam_role_policy" "ci_artifacts" {
  name   = "${var.project_name}-${var.environment}-ci-artifacts"
  role   = aws_iam_role.instance.id
  policy = data.aws_iam_policy_document.ci_artifacts.json
}
