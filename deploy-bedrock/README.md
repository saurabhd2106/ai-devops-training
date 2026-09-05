# deploy-bedrock — Terraform Amazon Bedrock access setup

Configures **IAM invoke access**, optional **foundation model agreements**, **CloudWatch invocation logging**, and an optional **Guardrail** using the **HashiCorp AWS provider `~> 6.62`**.

Amazon Bedrock is a regional serverless API — Terraform does **not** install Bedrock. This stack prepares your account so applications can call selected foundation models safely.

## Architecture

- Attachable IAM policy scoped to configured foundation models (and optional inference profiles)
- Optional Marketplace/provider agreements via `aws_bedrock_foundation_model_agreement`
- Optional Anthropic first-time use-case form (`aws_bedrock_use_case_for_model_access`)
- Regional invocation logging to CloudWatch Logs (14-day retention by default)
- Optional Guardrail: STANDARD content filters (MEDIUM) + managed PROFANITY list

```text
Caller IAM principal
  └─ invoke policy (output ARN)
       └─ Bedrock InvokeModel / Converse
            ├─ Foundation models / inference profiles
            ├─ Optional Guardrail
            └─ CloudWatch Logs (invocation logging)
```

Terraform does **not** call models, create Knowledge Bases, Agents, or OpenSearch Serverless.

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) `>= 1.5.7`
- AWS credentials configured (`AWS_PROFILE`, env keys, or SSO)
- Prefer a Bedrock-supported region with the models you need (default `us-east-1`)

## Quick start

```bash
cd deploy-bedrock

cp terraform.tfvars.example terraform.tfvars
# Adjust models{}, logging, or guardrail as needed

terraform init
terraform plan
terraform apply
```

### Customize models

```hcl
models = {
  nova_lite = {
    model_id          = "amazon.nova-lite-v1:0"
    inference_profile = "us.amazon.nova-lite-v1:0"
    accept_agreement  = false
  }
  titan_embed = {
    model_id         = "amazon.titan-embed-text-v2:0"
    accept_agreement = false
  }
  claude_sonnet = {
    model_id          = "anthropic.claude-sonnet-4-20250514-v1:0"
    inference_profile = "us.anthropic.claude-sonnet-4-20250514-v1:0"
    accept_agreement  = true
  }
  claude_haiku = {
    model_id          = "anthropic.claude-haiku-4-5-20251001-v1:0"
    inference_profile = "us.anthropic.claude-haiku-4-5-20251001-v1:0"
    accept_agreement  = true
  }
}
```

Anthropic models require `accept_agreement = true` and typically `enable_anthropic_use_case = true` on first use.

Enable the Guardrail:

```hcl
enable_guardrail = true
```

## After apply

```bash
terraform output invoke_policy_arn
terraform output example_converse_command
```

Attach the invoke policy to your caller role (EC2 instance profile, ECS task role, Lambda role, or IAM user):

```bash
aws iam attach-role-policy \
  --role-name YOUR_CALLER_ROLE \
  --policy-arn "$(terraform output -raw invoke_policy_arn)"
```

Then invoke Bedrock with the AWS CLI or SDK (Terraform will not call models for you).

## Destroy

```bash
terraform destroy
```

**Note:** If you enabled `enable_anthropic_use_case`, destroy removes the resource from state but does **not** delete the use-case submission in the account (AWS API limitation).

## Variables

| Name | Required | Default | Description |
|------|----------|---------|-------------|
| `aws_region` | no | `us-east-1` | AWS region |
| `project_name` | no | `deploy-bedrock` | Tag / name prefix |
| `environment` | no | `development` | `development` \| `staging` \| `production` \| `testing` |
| `models` | no | nova_lite + titan_embed | Map of model IDs / optional inference profiles / agreements |
| `enable_invocation_logging` | no | `true` | CloudWatch invocation logging (regional singleton) |
| `log_retention_days` | no | `14` | CloudWatch Logs retention |
| `enable_guardrail` | no | `false` | Create a content + profanity Guardrail |
| `guardrail_name` | no | `deploy-bedrock-guardrail` | Guardrail name |
| `enable_anthropic_use_case` | no | `false` | Submit Anthropic first-time use-case form |
| `anthropic_use_case_form` | no | example values | Form fields when Anthropic use-case is enabled |

## Security defaults

- IAM invoke policy scoped to listed foundation model and inference profile ARNs
- Guardrail `ApplyGuardrail` only when a Guardrail is created
- Logging role trusted only by `bedrock.amazonaws.com` with source account/ARN conditions
- Encrypted CloudWatch Logs group (AWS-managed key) with finite retention
- No IAM users or long-lived access keys created by this stack

## Estimated monthly cost (us-east-1)

Idle stack is near **$0**. You pay when you invoke:

| Item | Approx cost |
|------|-------------|
| Foundation model On-Demand | Per input/output token (model-specific) |
| Guardrail | Per text unit processed |
| CloudWatch Logs | ~$0.50 / GB ingested; storage by retention |

OpenSearch Serverless for Knowledge Bases is **not** created (that alone is typically a ~$345/month OCU minimum).

Optional pre-apply scan:

```bash
checkov -d .
```

## Optional remote state

Local state is used by default. Uncomment and configure the S3 backend in `versions.tf` for team use.

## Caveats

- **Region-specific:** Bedrock and each model are not available in every region. Confirm availability before changing `aws_region`.
- **Model access:** Amazon first-party models are typically usable with IAM alone after AWS’s simplified model access. Third-party models may still need `accept_agreement = true` and, for Anthropic, `enable_anthropic_use_case = true`.
- **Invocation logging is a per-region singleton.** Only one configuration should manage it for a given region — do not define this resource in another root module for the same region.
- **Inference profiles:** Cross-region profiles (e.g. `us.amazon.nova-lite-v1:0`) improve availability; include them in `models` when you plan to call them.

## Out of scope

- Knowledge Bases, Agents, Flows, or Data Automation
- OpenSearch Serverless / Pinecone / Aurora vector stores
- Fine-tuning, custom model import, or Provisioned Throughput
- Attaching the IAM policy to deploy-vm / ECS / EKS roles (attach the output ARN yourself)
- VPC interface endpoints for Bedrock
