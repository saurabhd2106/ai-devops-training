# deploy-ecr — Terraform private ECR provisioning

Provisions private Amazon ECR repositories using the **HashiCorp AWS provider `~> 6.62`**, with scan-on-push, SSE-S3 encryption, lifecycle cleanup, and an attachable IAM push/pull policy.

## Architecture

- One private ECR repository per entry in the `repositories` map
- Repository name pattern: `{project_name}/{key}` (default `deploy-ecr/app`)
- Basic image scanning on push (no Amazon Inspector enhanced scanning)
- Encryption at rest: **AES256** (SSE-S3) by default; optional `KMS`
- Lifecycle: expire untagged images after 7 days; keep last N tagged images
- Same-account repository policy (no public or cross-account access)
- Managed IAM policy you can attach later to Jenkins/CI/EC2 roles

Terraform does **not** build or push container images — only the registry resources.

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) `>= 1.5.7`
- AWS credentials configured (`AWS_PROFILE`, env keys, or SSO)
- Docker (only if you plan to push images after apply)

## Quick start

```bash
cd deploy-ecr

cp terraform.tfvars.example terraform.tfvars
# Adjust repositories{}, region, or encryption as needed

terraform init
terraform plan
terraform apply
```

### Customize repositories

```hcl
repositories = {
  app = {
    mutable         = true
    scan_on_push    = true
    max_image_count = 10
  }
  api = {
    mutable         = false   # IMMUTABLE tags
    scan_on_push    = true
    max_image_count = 20
  }
  worker = {
    enabled = false           # skip without removing from the map
  }
}
```

## Push an image

```bash
terraform output docker_login_command
# run the printed command, then:

terraform output -json docker_push_commands
# or manually:
docker tag myapp:latest <repository_url>:latest
docker push <repository_url>:latest
```

Example login (replace account ID from `terraform output registry_id`):

```bash
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin <account>.dkr.ecr.us-east-1.amazonaws.com
```

## Attach push/pull to CI (optional)

```bash
terraform output push_pull_policy_arn
# Attach that policy ARN to your Jenkins/EC2/CI IAM role (separate from this stack).
```

## Destroy

```bash
terraform destroy
```

With `force_delete = true` (default), repositories that still contain images are deleted.

## Variables

| Name | Required | Default | Description |
|------|----------|---------|-------------|
| `aws_region` | no | `us-east-1` | AWS region |
| `project_name` | no | `deploy-ecr` | Tag / repo name prefix |
| `environment` | no | `development` | `development` \| `staging` \| `production` \| `testing` |
| `repositories` | no | `app` map | Per-repo `enabled`, `mutable`, `scan_on_push`, `max_image_count` |
| `encryption_type` | no | `AES256` | `AES256` or `KMS` |
| `kms_key` | no | `null` | KMS key when using `KMS` (AWS-managed if null) |
| `untagged_expiry_days` | no | `7` | Expire untagged images after N days |
| `force_delete` | no | `true` | Allow destroy when images remain |

## Security defaults

- Private repositories only
- Repository policy: same AWS account root (not public)
- Scan on push enabled by default
- Encryption at rest (AES256)
- IAM policy scoped to created repo ARNs (`GetAuthorizationToken` on `*` as required by AWS)
- No IAM users or long-lived access keys

## Estimated monthly cost (us-east-1)

Empty repositories cost **$0**. Approximate list prices:

| Item | Approx cost |
|------|-------------|
| Storage | $0.10 / GB-month (e.g. 5 GB ≈ **$0.50/month**) |
| Basic scan-on-push | Included |
| Data transfer (in-region pull) | Typically $0 for same-region AWS pulls |
| Enhanced scanning (Inspector) | **Not enabled** |

Lifecycle rules limit retained images so storage does not grow unbounded.

Optional pre-apply scan:

```bash
checkov -d .
```

## Optional remote state

Local state is used by default. Uncomment and configure the S3 backend in `versions.tf` for team use.

## Out of scope

- Building or pushing application images
- Attaching the IAM policy to deploy-vm Jenkins (attach the output ARN yourself)
- ECS, EKS, Fargate, or VPC interface endpoints
- Cross-account replication or ECR Public
