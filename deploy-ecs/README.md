# deploy-ecs — Terraform ECS Fargate provisioning

Provisions an Amazon ECS **Fargate** cluster with an Application Load Balancer, private-subnet tasks, ECR repositories, and a configurable map of container services — using the **HashiCorp AWS provider `~> 6.62`**, matching the style of `deploy-vm`.

## Architecture

- Dedicated VPC (`10.0.0.0/16`) with **2 public** and **2 private** subnets (two AZs)
- Internet-facing **ALB** in public subnets; **Fargate tasks** in private subnets (no public IPs)
- Single **NAT Gateway** for outbound image pulls and AWS API calls (dev cost-conscious)
- One ECS service per entry in the `services` map; path-based ALB rules for multiple apps
- Optional **HTTPS** when `acm_certificate_arn` is set (HTTP → HTTPS redirect)
- **ECS Exec** enabled for interactive debugging into running tasks
- CloudWatch Logs per service (14-day retention)

| Role | Default image | CPU / memory | Port | Path |
|------|---------------|--------------|------|------|
| `app` | `public.ecr.aws/docker/library/nginx:stable` | 0.5 vCPU / 1 GiB | 80 | `/*` |

Terraform creates ECR repos when `create_ecr = true`. The default `image` is a public nginx image so `apply` serves traffic immediately. Point `image` at your ECR URL after you push.

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) `>= 1.5.7`
- AWS credentials configured (`AWS_PROFILE`, env keys, or SSO)
- Your current public IP (for the ALB ingress CIDR)

```bash
curl -s ifconfig.me
```

## Quick start

```bash
cd deploy-ecs

cp terraform.tfvars.example terraform.tfvars
# Set allowed_ingress_cidr; adjust services{} as needed

# Or inject via env:
#   export TF_VAR_allowed_ingress_cidr="$(curl -s ifconfig.me)/32"

terraform init
terraform plan
terraform apply
```

Open the ALB URL from your allowed CIDR:

```bash
terraform output alb_url
```

### Customize services

```hcl
services = {
  app = {
    image             = "123456789012.dkr.ecr.us-east-1.amazonaws.com/deploy-ecs-development-app:latest"
    cpu               = 512
    memory            = 1024
    container_port    = 80
    desired_count     = 1
    path_pattern      = "/*"
    listener_priority = 100
    create_ecr        = true
    health_check_path = "/"
  }
  api = {
    image             = "public.ecr.aws/docker/library/httpd:2.4"
    cpu               = 256
    memory            = 512
    container_port    = 80
    desired_count     = 1
    path_pattern      = "/api*"
    listener_priority = 50
    create_ecr        = true
    health_check_path = "/"
  }
}
```

Set `enabled = false` on a service to skip creating it without removing it from the map.

### Push your own image to ECR

```bash
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin <account>.dkr.ecr.us-east-1.amazonaws.com

# After apply, get the repo URL:
terraform output ecr_repository_urls

docker tag my-app:latest <ecr_url>:latest
docker push <ecr_url>:latest
```

Then set `services.app.image` to that URL (with tag) and run `terraform apply` again.

### Java app (sample-java-app) on Fargate

For [`sample-java-app/Jenkinsfile.ecs`](../sample-java-app/Jenkinsfile.ecs), configure the `app` service for Spring Boot (see `terraform.tfvars.example`):

- `container_port = 8080`
- `health_check_path = "/health"`
- `image` = your `deploy-ecr/sonarqube-java-demo` URL (or let CI update the task definition after the first push)
- `create_ecr = false` if images live in the separate [`deploy-ecr`](../deploy-ecr) stack

Attach the CI deploy policy to the Jenkins instance role:

```bash
terraform output -raw ci_deploy_policy_arn
# Set ecs_deploy_policy_arn in ../deploy-vm/terraform.tfvars, then:
terraform -chdir=../deploy-vm apply
```

Also attach `deploy-ecr` `push_pull_policy_arn` as `ecr_push_pull_policy_arn` on `deploy-vm` so Jenkins can push images.

### ECS Exec (debug)

```bash
terraform output list_tasks_commands
# Run the listed command, then:
aws ecs execute-command \
  --cluster $(terraform output -raw ecs_cluster_name) \
  --task <TASK_ID> \
  --container app \
  --interactive \
  --command /bin/sh \
  --region us-east-1
```

Requires [Session Manager plugin](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html) locally.

## Destroy

```bash
terraform destroy
```

NAT Gateway and ALB bill by the hour — destroy when idle.

## Variables

| Name | Required | Default | Description |
|------|----------|---------|-------------|
| `allowed_ingress_cidr` | **yes** | — | CIDR for ALB HTTP/HTTPS. Prefer `/32`. |
| `services` | no | one `app` service | Map of Fargate services |
| `aws_region` | no | `us-east-1` | AWS region |
| `project_name` | no | `deploy-ecs` | Tag / name prefix |
| `environment` | no | `development` | `development` \| `staging` \| `production` \| `testing` |
| `acm_certificate_arn` | no | `""` | Enables HTTPS :443 + HTTP redirect |
| `enable_container_insights` | no | `false` | ECS Container Insights |
| `vpc_cidr` | no | `10.0.0.0/16` | VPC CIDR |
| `public_subnet_cidrs` | no | two `/24`s | Public subnets (exactly 2) |
| `private_subnet_cidrs` | no | two `/24`s | Private subnets (exactly 2) |

## Security defaults

- Tasks in **private** subnets; ALB is the only public component
- ALB ingress restricted to `allowed_ingress_cidr`
- Task security groups: inbound from ALB SG only; outbound HTTPS (443) for ECR/AWS APIs
- ECR: scan on push, AES-256 encryption, lifecycle keep last 10 images
- IAM: execution role for pull/logs; task role limited to ECS Exec (`ssmmessages`); optional `ci_deploy` policy for Jenkins
- Optional TLS 1.2+ via existing ACM certificate (not created by this stack)

## Outputs (CI-related)

| Output | Use |
|--------|-----|
| `ci_deploy_policy_arn` | Set as `ecs_deploy_policy_arn` on [`deploy-vm`](../deploy-vm) so Jenkins can register task defs and update services |
| `ecs_cluster_name` | Jenkins parameter `ECS_CLUSTER` |
| `service_names` | Jenkins parameter `ECS_SERVICE` (default `app`) |
| `alb_url` | Smoke-test after deploy |

## Estimated monthly cost (us-east-1, On-Demand, 24/7)

Approximate list prices for the **default** one-service layout:

| Resource | Approx. |
|----------|---------|
| Fargate 0.5 vCPU / 1 GiB (1 task) | ~$18 |
| ALB (hours; low LCU) | ~$16–22 |
| NAT Gateway (1 AZ) + public IPv4 | ~$36–40 |
| ECR + CloudWatch Logs (small) | ~$1–3 |
| **Total (default 1 service)** | **~$70–85/month** |

Assumptions: continuous uptime, single NAT (not multi-AZ), negligible data transfer. Extra services add ~$18 each at the same Fargate size. NAT is the largest line item.

Optional pre-apply scan:

```bash
checkov -d .
```

## Optional remote state

Local state is used by default. Uncomment and configure the S3 backend in `versions.tf` for team use.

## Out of scope

- Route 53 / custom DNS (point your domain at `alb_dns_name` manually)
- RDS, EFS, WAF, Auto Scaling policies
- SonarQube / Jenkins install (use `deploy-vm` + `install-*` for persistent VMs)
- Automated `terraform apply` from CI (image rollouts use `ecs update-service`, not Terraform)
