# deploy-eks — Terraform Amazon EKS provisioning

Provisions a development-sized **Amazon EKS** cluster with a dedicated multi-AZ VPC and one managed node group using the **HashiCorp AWS provider `~> 6.62`**.

## Architecture

- Dedicated VPC (`10.20.0.0/16` by default) with **2 public + 2 private** subnets across 2 AZs
- Internet Gateway + **1 NAT Gateway** (dev cost control; private nodes egress via NAT)
- EKS control plane on private subnets; public API endpoint restricted to `allowed_api_cidr` (+ optional `additional_api_cidrs`)
- One managed node group (`t3.medium` x2 by default) in private subnets
- Encrypted gp3 root volumes, IMDSv2 required, KMS encryption for Kubernetes secrets
- Cluster upgrade policy: **STANDARD** support (avoids extended-support surcharge)
- Access mode: **API** with bootstrap cluster-creator admin permissions (no `aws-auth` ConfigMap)
- Optional Jenkins CI: `ci_principal_arn` access entry + `ci_deploy` IAM policy for kubectl from `deploy-vm`

```
                    ┌─ allowed_api_cidr (+ additional) ─┐
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
- Your current public IP (for the API CIDR)

```bash
curl -s ifconfig.me
```

## Quick start

```bash
cd deploy-eks

cp terraform.tfvars.example terraform.tfvars
# Set allowed_api_cidr to YOUR_IP/32

# Or inject via env:
#   export TF_VAR_allowed_api_cidr="$(curl -s ifconfig.me)/32"

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
cluster_version     = "1.34"
```

### Wire Jenkins for kubectl deploy

After [`deploy-vm`](../deploy-vm) exists:

```bash
# 1. Grant the instance role EKS cluster admin + allow Jenkins public IP on the API
terraform -chdir=../deploy-vm output -raw instance_role_arn
terraform -chdir=../deploy-vm output -json public_ips
# Set in terraform.tfvars:
#   ci_principal_arn     = "<instance_role_arn>"
#   additional_api_cidrs = ["<jenkins-public-ip>/32"]
terraform apply

# 2. Attach the CI IAM policy on deploy-vm
terraform output -raw ci_deploy_policy_arn
# Set eks_deploy_policy_arn in ../deploy-vm/terraform.tfvars, then:
terraform -chdir=../deploy-vm apply
```

Then create a Jenkins job with Script Path `sample-java-app/Jenkinsfile.eks`.

## Destroy

```bash
terraform destroy
```

Destroy also takes ~10–15 minutes (node group, then cluster, then VPC/NAT).

## Variables

| Name | Required | Default | Description |
|------|----------|---------|-------------|
| `allowed_api_cidr` | **yes** | — | CIDR for EKS public API (`/32` recommended). `0.0.0.0/0` rejected. |
| `additional_api_cidrs` | no | `[]` | Extra API CIDRs (e.g. Jenkins public IP `/32`). `0.0.0.0/0` rejected. |
| `ci_principal_arn` | no | `null` | IAM role ARN for EKS access entry (Jenkins instance role from `deploy-vm`) |
| `aws_region` | no | `us-east-1` | AWS region |
| `project_name` | no | `deploy-eks` | Tag / name prefix |
| `environment` | no | `development` | `development` \| `staging` \| `production` \| `testing` |
| `cluster_version` | no | `1.34` | Kubernetes version |
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

- Public API endpoint restricted to `allowed_api_cidr` and optional `additional_api_cidrs` (not open to the world)
- Private endpoint enabled; worker nodes use private subnets only
- Kubernetes secrets encrypted with a dedicated KMS key (rotation enabled)
- Node EBS: **gp3**, **encrypted**, delete on termination
- **IMDSv2 required**, hop limit `1`
- Node IAM: `AmazonEKSWorkerNodePolicy`, `AmazonEKS_CNI_Policy`, `AmazonEC2ContainerRegistryPullOnly`, `AmazonSSMManagedInstanceCore`
- Upgrade policy: **STANDARD** (no extended-support billing)
- Optional CI: EKS access entry (`AmazonEKSClusterAdminPolicy`) + scoped `ci_deploy` IAM policy

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
