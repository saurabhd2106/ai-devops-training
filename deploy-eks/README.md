# deploy-eks — Terraform Amazon EKS provisioning

Provisions a development-sized **Amazon EKS** cluster with a dedicated multi-AZ VPC and one managed node group using the **HashiCorp AWS provider `~> 6.62`**.

## Architecture

- Dedicated VPC (`10.20.0.0/16` by default) with **2 public + 2 private** subnets across 2 AZs
- Internet Gateway + **1 NAT Gateway** (dev cost control; private nodes egress via NAT)
- EKS control plane on private subnets; public API endpoint defaults to `0.0.0.0/0` for demo labs (override `allowed_api_cidr` to lock down)
- One managed node group (`t3.medium` x2 by default) in private subnets
- Encrypted gp3 root volumes, IMDSv2 required, KMS encryption for Kubernetes secrets
- Cluster upgrade policy: **STANDARD** support (avoids extended-support surcharge)
- Access mode: **API** with bootstrap cluster-creator admin permissions (no `aws-auth` ConfigMap)
- Optional Jenkins CI: `ci_principal_arn` access entry + `ci_deploy` IAM policy for kubectl from `deploy-vm`

```
                    ┌─ allowed_api_cidr (default 0.0.0.0/0) ─┐
kubectl / Jenkins ──► EKS public API ────► Control plane
                                              │
VPC 10.20.0.0/16                              ▼
  public AZ-a / AZ-b  (ELB tags)         private AZ-a / AZ-b
       │                                      │
       └── NAT (AZ-a) ◄── node egress ────────┘
                            managed nodes (t3.medium)
```

Terraform does **not** deploy application workloads, Ingress Controllers, or Cluster Autoscaler — only the cluster, network, and optional CI access wiring. Workloads are applied by [`sample-java-app/Jenkinsfile.eks`](../sample-java-app/Jenkinsfile.eks).

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) `>= 1.5.7`
- AWS credentials configured (`AWS_PROFILE`, env keys, or SSO)
- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) v2 and [kubectl](https://kubernetes.io/docs/tasks/tools/)

## Quick start

```bash
cd deploy-eks

cp terraform.tfvars.example terraform.tfvars
# Optional: set allowed_api_cidr to YOUR_IP/32 to lock the lab down
# (default is 0.0.0.0/0 for demo labs)

terraform init
terraform plan
terraform apply
```

Cluster creation typically takes **15–20 minutes**.

### Connect with kubectl

```bash
terraform output -raw kubeconfig_command
# or:
aws eks update-kubeconfig --name deploy-eks-development --region us-east-1

kubectl get nodes
kubectl get pods -A
```

### Customize node sizing

```hcl
node_instance_types = ["t3.large"]
node_desired_size   = 2
node_min_size       = 1
node_max_size       = 4
node_disk_size      = 30
cluster_version     = "1.36"
```

### Wire Jenkins for kubectl deploy (Terraform AuthN/AuthZ)

Jenkins uses the **`deploy-vm` EC2 instance role** only — no IAM User, access keys, or manual `create-access-entry` CLI.

AuthN: attach IAM policies on the instance role. AuthZ: EKS access entry for that same role ARN.

```bash
# 0. Prerequisites: deploy-vm and deploy-ecr already applied
terraform -chdir=../deploy-vm output -raw instance_role_arn

# 1. deploy-eks — AuthZ (access entry). Public API defaults to 0.0.0.0/0 for demo labs.
# In terraform.tfvars:
#   ci_principal_arn = "<instance_role_arn>"
# Optional: if you narrowed allowed_api_cidr, also add Jenkins:
#   additional_api_cidrs = ["<jenkins-public-ip>/32"]
terraform apply

# 2. deploy-vm — AuthN (attach ECR + EKS CI policies to the instance role)
terraform output -raw ci_deploy_policy_arn
# In ../deploy-vm/terraform.tfvars:
#   ecr_push_pull_policy_arn = "<from deploy-ecr>"
#   eks_deploy_policy_arn    = "<ci_deploy_policy_arn above>"
terraform -chdir=../deploy-vm apply

# 3. install-jenkins — permanent kubectl at /usr/local/bin/kubectl
# ansible-playbook site.yml  (from install-jenkins/)
```

Then create a Jenkins job with Script Path `sample-java-app/Jenkinsfile.eks`. The agent authenticates with the instance profile via `aws eks update-kubeconfig`.

## Destroy

```bash
terraform destroy
```

Destroy also takes ~10–15 minutes (node group, then cluster, then VPC/NAT).

## Variables

| Name | Required | Default | Description |
|------|----------|---------|-------------|
| `allowed_api_cidr` | no | `0.0.0.0/0` | CIDR for EKS public API. Open for demo labs; set a `/32` to lock down. |
| `additional_api_cidrs` | no | `[]` | Extra API CIDRs (e.g. Jenkins public IP `/32` when `allowed_api_cidr` is narrowed). |
| `ci_principal_arn` | no | `null` | IAM principal ARN for EKS access entry — use the Jenkins **instance role** ARN from `deploy-vm` (Terraform AuthZ; no IAM User) |
| `aws_region` | no | `us-east-1` | AWS region |
| `project_name` | no | `deploy-eks` | Tag / name prefix |
| `environment` | no | `development` | `development` \| `staging` \| `production` \| `testing` |
| `cluster_version` | no | `1.36` | Kubernetes version |
| `vpc_cidr` | no | `10.20.0.0/16` | VPC CIDR (distinct from deploy-vm) |
| `public_subnet_cidrs` | no | `10.20.0.0/24`, `10.20.1.0/24` | Exactly 2 public CIDRs |
| `private_subnet_cidrs` | no | `10.20.10.0/24`, `10.20.11.0/24` | Exactly 2 private CIDRs |
| `node_instance_types` | no | `["t3.medium"]` | Managed node instance types |
| `node_desired_size` | no | `2` | Desired node count |
| `node_min_size` | no | `1` | Minimum node count |
| `node_max_size` | no | `3` | Maximum node count |
| `node_disk_size` | no | `20` | Root volume GiB (gp3, encrypted) |
| `enable_cluster_logs` | no | `false` | Control-plane CloudWatch logs |

## Security defaults

- Public API endpoint defaults to `0.0.0.0/0` for demo labs; set `allowed_api_cidr` (and optional `additional_api_cidrs`) to restrict if needed
- Private endpoint enabled; worker nodes use private subnets only
- Kubernetes secrets encrypted with a dedicated KMS key (rotation enabled)
- Node EBS: **gp3**, **encrypted**, delete on termination
- **IMDSv2 required**, hop limit `1`
- Node IAM: `AmazonEKSWorkerNodePolicy`, `AmazonEKS_CNI_Policy`, `AmazonEC2ContainerRegistryPullOnly`, `AmazonSSMManagedInstanceCore`
- Upgrade policy: **STANDARD** (no extended-support billing)
- Optional CI: EKS access entry for the Jenkins **instance role** (`AmazonEKSClusterAdminPolicy`) + scoped `ci_deploy` IAM policy (Terraform only; no IAM User)

## Estimated monthly cost (us-east-1, On-Demand, 24/7)

Approximate list prices for the **default** layout:

| Component | Approx. |
|-----------|---------|
| EKS control plane (standard support, $0.10/hr) | ~$73 |
| 2x `t3.medium` | ~$61 |
| 2x 20 GiB gp3 | ~$3 |
| 1 NAT Gateway | ~$33 |
| NAT Elastic IP (public IPv4) | ~$4 |
| **Total** | **~$170–180/month** |

Assumptions: continuous uptime, no control-plane logs, negligible data transfer. NAT data processing and inter-AZ traffic are extra. Destroy when idle.

Optional pre-apply scan:

```bash
checkov -d .
```

## Optional remote state

Local state is used by default. Uncomment and configure the S3 backend in `versions.tf` for team use.

## Out of scope

- IRSA / OIDC provider
- VPC CNI / CoreDNS / kube-proxy / EBS CSI addon customization
- AWS Load Balancer Controller, Cluster Autoscaler
- Sample application Deployment/Service (applied by Jenkins via [`Jenkinsfile.eks`](../sample-java-app/Jenkinsfile.eks))
- Multi-NAT / production HA networking
- Automated `terraform apply` from CI
