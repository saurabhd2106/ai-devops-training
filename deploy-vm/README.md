# deploy-vm — Terraform multi-role EC2 provisioning

Provisions named Amazon EC2 VMs (app, SonarQube, Jenkins by default) in a dedicated public VPC using the **HashiCorp AWS provider `~> 6.62`**, with per-VM instance types, disk sizes, and ingress ports. Also creates a private **CI artefacts S3 bucket** and allows Jenkins to reach SonarQube for scans.

## Architecture

- Dedicated VPC (`10.0.0.0/16`) with one public subnet and an Internet Gateway
- One EC2 instance per entry in the `vms` map (Amazon Linux 2023 via SSM Parameter Store)
- Shared SSH key pair and IAM instance profile (SSM Session Manager + CI S3 access)
- Per-VM security group: TCP/22 plus role `ingress_ports`, all from `allowed_ssh_cidr` only
- Extra ingress: **Jenkins SG → SonarQube SG on TCP 9000** (when both roles are enabled) so CI can run SonarScanner
- Private S3 bucket for Jenkins artefact uploads (SSE-S3, all public access blocked)
- Encrypted gp3 root volume, IMDSv2 required

| Role | Default type | Root disk | Ports (from allowed CIDR) |
|------|--------------|-----------|---------------------------|
| `app` | `t3.small` | 30 GiB | 22, 80, 443 |
| `sonarqube` | `t3.medium` | 50 GiB | 22, 9000 (+ 9000 from Jenkins SG) |
| `jenkins` | `t3.medium` | 40 GiB | 22, 8080 |

Terraform does **not** install Jenkins, SonarQube, or your app — only the VMs, network, and CI S3/IAM. Install Jenkins after connect with sibling [`install-jenkins`](../install-jenkins/README.md). Install SonarQube with sibling [`install-sonarqube`](../install-sonarqube/README.md). Pipeline for the Java demo: [`sample-java-app/Jenkinsfile`](../sample-java-app/Jenkinsfile).

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) `>= 1.5.7`
- AWS credentials configured (`AWS_PROFILE`, env keys, or SSO)
- An OpenSSH public key (e.g. `~/.ssh/id_ed25519.pub`)
- Your current public IP (for the access CIDR)

```bash
curl -s ifconfig.me
```

## Quick start

```bash
cd deploy-vm

cp terraform.tfvars.example terraform.tfvars
# Set allowed_ssh_cidr and ssh_public_key; adjust vms{} types/sizes as needed

# Or inject via env:
#   export TF_VAR_ssh_public_key="$(cat ~/.ssh/id_ed25519.pub)"
#   export TF_VAR_allowed_ssh_cidr="$(curl -s ifconfig.me)/32"

terraform init
terraform plan
terraform apply
```

### Customize machine types and sizes

```hcl
vms = {
  app = {
    instance_type    = "t3.large"
    root_volume_size = 50
    ingress_ports    = [80, 443]
  }
  sonarqube = {
    instance_type    = "t3.xlarge"
    root_volume_size = 100
    ingress_ports    = [9000]
  }
  jenkins = {
    instance_type    = "t3.medium"
    root_volume_size = 40
    ingress_ports    = [8080]
    enabled          = false   # skip this VM
  }
}
```

Add more roles by adding keys to the map (e.g. `monitoring = { instance_type = "t3.micro", ingress_ports = [3000] }`).

## Connect

```bash
terraform output instances
terraform output ssh_commands
terraform output public_ips
terraform output private_ips
terraform output -raw ci_artifacts_bucket
```

Use `private_ips.sonarqube` as the Jenkins environment variable `SONAR_HOST_URL` (`http://<ip>:9000`) and `ci_artifacts_bucket` as the Jenkins `S3_BUCKET` parameter for [`sample-java-app`](../sample-java-app).

### ECR publish (Jenkins)

After [`deploy-ecr`](../deploy-ecr) is applied, attach its push/pull policy to this stack’s instance role so Jenkins can log in and push images:

```bash
terraform -chdir=../deploy-ecr output -raw push_pull_policy_arn
# Set ecr_push_pull_policy_arn in terraform.tfvars to that ARN, then:
terraform apply
```

Confirm with `terraform output instance_role_name` / `instance_role_arn`.

Example SSH (Amazon Linux 2023 user is `ec2-user`):

```bash
ssh -i ~/.ssh/id_ed25519 ec2-user@<app-public-ip>
```

UI endpoints (from your allowed CIDR):

- App: `http://<app-ip>/` or `https://<app-ip>/`
- SonarQube: `http://<sonarqube-ip>:9000` — install software with [`install-sonarqube`](../install-sonarqube/README.md)
- Jenkins: `http://<jenkins-ip>:8080` — install software with [`install-jenkins`](../install-jenkins/README.md)

SSM backup access:

```bash
aws ssm start-session --target <instance-id> --region us-east-1
```

## Destroy

```bash
terraform destroy
```

## Variables

| Name | Required | Default | Description |
|------|----------|---------|-------------|
| `allowed_ssh_cidr` | **yes** | — | CIDR for SSH + role ports (`/32` recommended; `0.0.0.0/0` allowed for test access) |
| `ssh_public_key` | **yes** | — | OpenSSH public key material |
| `vms` | no | app / sonarqube / jenkins map | Per-VM `instance_type`, `root_volume_size`, `ingress_ports`, `enabled` |
| `aws_region` | no | `us-east-1` | AWS region |
| `project_name` | no | `deploy-vm` | Tag / name prefix |
| `environment` | no | `development` | `development` \| `staging` \| `production` \| `testing` |
| `key_name` | no | `deploy-vm-key` | Key pair name prefix |
| `enable_detailed_monitoring` | no | `false` | 1-minute CloudWatch metrics (extra cost) |
| `ecr_push_pull_policy_arn` | no | `null` | IAM policy ARN from `deploy-ecr` `push_pull_policy_arn` for Jenkins ECR push/pull |

## Security defaults

- SSH and app/UI ports restricted to `allowed_ssh_cidr`
- EBS root: **gp3**, **encrypted**, delete on termination
- **IMDSv2 required**, hop limit `1`
- Shared IAM with `AmazonSSMManagedInstanceCore` (and optional `ecr_push_pull_policy_arn` for ECR)
- AMI pinned after first apply (`lifecycle.ignore_changes = [ami]`)

## Estimated monthly cost (us-east-1, On-Demand, 24/7)

Approximate list prices for **default** three-VM layout:

| VM | Compute (approx) | gp3 | Public IPv4 | Subtotal |
|----|------------------|-----|-------------|----------|
| app (`t3.small`, 30 GiB) | ~$15.18 | ~$2.40 | ~$3.65 | ~$21 |
| sonarqube (`t3.medium`, 50 GiB) | ~$30.37 | ~$4.00 | ~$3.65 | ~$38 |
| jenkins (`t3.medium`, 40 GiB) | ~$30.37 | ~$3.20 | ~$3.65 | ~$37 |
| **Total (all three)** | | | | **~$80–96/month** |

Assumptions: continuous uptime, basic monitoring, no NAT Gateway, negligible data transfer. Disable a role with `enabled = false`, or stop instances when idle.

Optional pre-apply scan:

```bash
checkov -d .
```

## Optional remote state

Local state is used by default. Uncomment and configure the S3 backend in `versions.tf` for team use.

## CI artefacts (S3)

| Output | Use |
|--------|-----|
| `ci_artifacts_bucket` | Jenkins pipeline parameter `S3_BUCKET` |
| `ci_artifacts_bucket_arn` | IAM / debugging |

Bucket name pattern: `{project_name}-{environment}-ci-artifacts-{account_id}`. Objects are written by Jenkins via the shared instance role (`s3:ListBucket`, `s3:GetObject`, `s3:PutObject` on that bucket).

## Out of scope

- Installing Jenkins (use sibling [`install-jenkins`](../install-jenkins/README.md)), SonarQube (use sibling [`install-sonarqube`](../install-sonarqube/README.md)), or application software
- NAT Gateway / private subnets
- Auto Scaling, ALB, Elastic IPs
- Automated `terraform apply` from CI
