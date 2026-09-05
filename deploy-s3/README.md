# deploy-s3 — Terraform private S3 bucket provisioning

Provisions a private Amazon S3 bucket using the **HashiCorp AWS provider `~> 6.62`**, with public access blocked, SSE-S3 encryption, versioning, HTTPS-only access, and incomplete multipart cleanup.

## Architecture

- One private general-purpose S3 bucket (not a website or CloudFront origin)
- Default name: `{project_name}-{environment}-{account_id}` (override with `bucket_name`)
- Block Public Access: all four settings enabled
- Object Ownership: **BucketOwnerEnforced** (ACLs disabled)
- Encryption at rest: **AES256** (SSE-S3) by default; optional `KMS`
- Versioning enabled by default
- Bucket policy denies requests that are not over HTTPS (`aws:SecureTransport`)
- Lifecycle: abort incomplete multipart uploads after 7 days

Terraform does **not** upload objects — only the bucket and security configuration.

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) `>= 1.5.7`
- AWS credentials configured (`AWS_PROFILE`, env keys, or SSO)

## Quick start

```bash
cd deploy-s3

cp terraform.tfvars.example terraform.tfvars
# Adjust region, project_name, environment, or bucket_name as needed

terraform init
terraform plan
terraform apply
```

### Custom bucket name

```hcl
bucket_name = "my-company-deploy-s3-dev"
```

Names must be globally unique across all AWS accounts.

### KMS encryption

```hcl
encryption_type = "KMS"
# kms_key       = "arn:aws:kms:us-east-1:123456789012:key/..."  # optional; AWS-managed aws/s3 if null
```

## Useful outputs

```bash
terraform output bucket_id
terraform output bucket_arn
terraform output bucket_domain_name
```

Example upload (after apply):

```bash
aws s3 cp ./file.txt s3://$(terraform output -raw bucket_id)/
```

## Destroy

```bash
terraform destroy
```

With `force_destroy = true` (default), the bucket is deleted even if it still contains objects.

## Variables

| Name | Required | Default | Description |
|------|----------|---------|-------------|
| `aws_region` | no | `us-east-1` | AWS region |
| `project_name` | no | `deploy-s3` | Tag / default name prefix |
| `environment` | no | `development` | `development` \| `staging` \| `production` \| `testing` |
| `bucket_name` | no | `null` | Explicit bucket name; auto-generated if unset |
| `enable_versioning` | no | `true` | Enable object versioning |
| `encryption_type` | no | `AES256` | `AES256` or `KMS` |
| `kms_key` | no | `null` | KMS key when using `KMS` (AWS-managed if null) |
| `force_destroy` | no | `true` | Allow destroy when objects remain |
| `abort_incomplete_multipart_days` | no | `7` | Abort incomplete multipart uploads after N days |

## Security defaults

- Private bucket only (Block Public Access on all four settings)
- Bucket owner enforced (no ACLs)
- Encryption at rest (AES256 by default)
- HTTPS-only via deny-insecure-transport bucket policy
- No IAM users or long-lived access keys

## Estimated monthly cost (us-east-1)

An empty bucket costs **$0**. Approximate list prices:

| Item | Approx cost |
|------|-------------|
| Standard storage | $0.023 / GB-month (e.g. 10 GB ≈ **$0.23/month**) |
| PUT / COPY / POST / LIST | $0.005 / 1,000 requests |
| GET / SELECT | $0.0004 / 1,000 requests |
| Data transfer out to internet | First 100 GB/month often free (AWS Free Tier / always-free tier varies); then ~$0.09/GB |

Versioning retains prior object versions, which increases storage until you add expiration rules (out of scope for this stack).

Optional pre-apply scan:

```bash
checkov -d .
```

## Optional remote state

Local state is used by default. Uncomment and configure the S3 backend in `versions.tf` for team use.

## Out of scope

- Static website hosting or CloudFront
- Public objects or bucket policies that allow anonymous access
- Access logging, replication, or inventory
- Attachable IAM read/write policies for CI roles
