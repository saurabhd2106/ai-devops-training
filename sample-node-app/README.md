# sonarqube-node-demo

Express demo for SonarQube training (intentional code-quality issues and one failing Jest test).

Local development only (not a deploy path): `npm install` | `npm start` | `npm test`.

All lab provisioning and CI/CD runs through **Terraform**, **Ansible**, or a **Jenkinsfile**.

## Execution contract

| Mechanism | Owns | How to run |
|-----------|------|------------|
| **Terraform** | AWS resources (VMs, S3 artefacts bucket, ECR, ECS, EKS, IAM) | `terraform apply` in `deploy-vm`, `deploy-ecr`, `deploy-ecs`, `deploy-eks` |
| **Ansible** | Tools on the Jenkins EC2 (Node 20, sonar-scanner, kubectl, …) | `ansible-playbook site.yml` in [`install-jenkins`](../install-jenkins) |
| **Jenkinsfile** | Build, test, SonarQube, publish, and deploy | Jenkins **Pipeline script from SCM** → Script Path below |

Supporting files (`Dockerfile`, `k8s/`, `ci/deploy-app.sh`) are consumed by Jenkinsfiles only. Do not run them by hand.

The shared Application VM (`Role=app`) and the single ECS `app` service can host **either** the Java sample **or** this Node sample at a time — not both.

## CI credentials and Jenkins setup

Do this after Terraform (`deploy-vm`) and Ansible (`install-sonarqube`, `install-jenkins`). Collect values once:

```bash
terraform -chdir=../deploy-vm output -json public_ips
terraform -chdir=../deploy-vm output -json private_ips
terraform -chdir=../deploy-vm output -json instance_ids
terraform -chdir=../deploy-vm output -raw ci_artifacts_bucket
```

| Value | Where to use it |
|-------|-----------------|
| SonarQube **private** IP `:9000` | Jenkins environment variable `SONAR_HOST_URL` |
| `ci_artifacts_bucket` | Jenkins environment variable `S3_BUCKET` |
| App instance ID (`instance_ids.app`) | Optional Jenkins env `APP_INSTANCE_ID` for [`Jenkinsfile.deploy-app`](Jenkinsfile.deploy-app) |
| App **public** IP | Verify VM deploy: `http://<app-public-ip>/health` |

### 1. Create a SonarQube token

1. Open `http://<sonarqube-public-ip>:9000` and sign in.
2. Avatar → **My Account** → **Security** → generate a **User Token** (e.g. `ci-sample-node-app`).
3. Use the same credential ID as the Java jobs: `sonarqube-token`.

### 2. Jenkins — credentials, tools, and environment

Open `http://<jenkins-public-ip>:8080`.

#### Credentials

1. Kind: **Secret text**
2. Secret: SonarQube token
3. ID: `sonarqube-token` (must match; Jenkinsfiles bind `credentials('sonarqube-token')`)

Optional AWS credentials ID `aws-ci` only if Jenkins is not using the `deploy-vm` instance profile.

#### Tools (Manage Jenkins → Tools)

| Tool | Name | Home / path |
|------|------|-------------|
| SonarQube Scanner | `sonar-scanner` | `/opt/sonar-scanner` |

Node 20 is installed by [`install-jenkins`](../install-jenkins) (`nodejs20` on PATH). Uncheck **Install automatically** for SonarScanner.

#### Environment variables (Manage Jenkins → System → Global properties)

1. Check **Environment variables**
2. **Add**:
   - `SONAR_HOST_URL` = `http://<sonarqube-private-ip>:9000`
   - `S3_BUCKET` = `terraform -chdir=../deploy-vm output -raw ci_artifacts_bucket`
   - `APP_INSTANCE_ID` (optional) = app instance ID from `deploy-vm`
3. **Save**

#### Pipeline jobs

Preferred: create all sample jobs and the **Java** / **Node** views with sibling [`jenkins-pipeline`](../jenkins-pipeline) (`cp jobs.env.example jobs.env` → `./create-jobs.sh`).

Or create each job by hand (**New Item** → Pipeline → **Pipeline script from SCM**):

| Job purpose | Script Path |
|-------------|-------------|
| Build / test / Sonar / S3 | `sample-node-app/Jenkinsfile` |
| Same + SSM deploy to Application VM | `sample-node-app/Jenkinsfile.deploy-app` |
| Docker build + ECR publish | `sample-node-app/Jenkinsfile.sonarqube-node-demo` |
| ECR + ECS deploy | `sample-node-app/Jenkinsfile.ecs` |
| ECR + EKS deploy | `sample-node-app/Jenkinsfile.eks` |

## Jenkins CI pipeline (S3)

Declarative pipeline: [`Jenkinsfile`](Jenkinsfile).

| Stage | What it does |
|-------|----------------|
| Checkout | SCM checkout; resolves `sample-node-app/` vs app-only root; fails early if `node`, `npm`, or `aws` is missing |
| Build | `npm ci` |
| Test | `npm run test:ci` (intentional failing test → **UNSTABLE**) + JUnit / coverage artefacts |
| Package | Production `npm ci --omit=dev` + tarball `sonarqube-node-demo-1.0.0.tgz` |
| SonarQube Scan | `sonar-scanner`; **UNSTABLE** on failure so S3 publish still runs |
| Publish artefacts | Jenkins archive + upload tarball/junit to S3 |

Artefacts:

- Jenkins: `sonarqube-node-demo-*.tgz`, junit XML, coverage
- S3: `s3://<bucket>/sample-node-app/<BUILD_NUMBER>/`

### Prerequisites (lab)

1. `terraform apply` in [`deploy-vm`](../deploy-vm)
2. `ansible-playbook site.yml` in [`install-sonarqube`](../install-sonarqube)
3. `ansible-playbook site.yml` in [`install-jenkins`](../install-jenkins) (includes Node 20)
4. Jenkins credential `sonarqube-token` and env vars above

## Jenkins CI + Application VM deploy

Declarative pipeline: [`Jenkinsfile.deploy-app`](Jenkinsfile.deploy-app). Same stages as above, then SSM deploy.

| Stage | What it does |
|-------|----------------|
| Checkout → Publish artefacts | Same as [`Jenkinsfile`](Jenkinsfile) |
| Deploy to Application VM | Upload [`ci/deploy-app.sh`](ci/deploy-app.sh) to S3; resolve app EC2 (`APP_INSTANCE_ID` or tag `Role=app`); SSM runs the script so the VM pulls the tarball, installs Node 20 if needed, writes systemd unit `sample-node-app` on port **80**, health-checks `/health` |

Verify: `http://<app-public-ip>/health`

Requires `deploy-vm` SSM deploy IAM (`ci_ssm_deploy.tf`). Do not run `deploy-app.sh` outside this Jenkinsfile.

## Jenkins CI/CD pipeline (ECR only)

Declarative pipeline: [`Jenkinsfile.sonarqube-node-demo`](Jenkinsfile.sonarqube-node-demo).

| Stage | What it does |
|-------|----------------|
| Checkout | Fails early if `docker` or `aws` is missing |
| Build / Test | `node:20` Docker image + Jest (**UNSTABLE** on intentional failure) |
| SonarQube | `sonarsource/sonar-scanner-cli` |
| Publish | `docker build` / push `${BUILD_NUMBER}` and `latest` to `deploy-ecr/sonarqube-node-demo` |

### Prerequisites

1. `terraform apply` in [`deploy-ecr`](../deploy-ecr) (includes `sonarqube-node-demo` repo)
2. Attach `push_pull_policy_arn` to `deploy-vm` as `ecr_push_pull_policy_arn`, then `terraform apply` in `deploy-vm`
3. Docker on the Jenkins agent (installed by [`install-jenkins`](../install-jenkins) when `jenkins_install_docker` is true)

## Jenkins CI/CD pipeline (ECR + ECS)

Declarative pipeline: [`Jenkinsfile.ecs`](Jenkinsfile.ecs).

| Stage | What it does |
|-------|----------------|
| Checkout → Publish ECR | Same as ECR-only job |
| Deploy ECS | Rewrite task definition image/port → `register-task-definition` → `update-service` → wait for stable |

### Job parameters (defaults)

| Parameter | Default |
|-----------|---------|
| `AWS_REGION` | `us-east-1` |
| `ECR_REPOSITORY` | `deploy-ecr/sonarqube-node-demo` |
| `ECS_CLUSTER` | `deploy-ecs-development-cluster` |
| `ECS_SERVICE` | `app` |
| `ECS_TASK_FAMILY` | `deploy-ecs-development-app` |
| `ECS_CONTAINER_NAME` | `app` |
| `ECS_CONTAINER_PORT` | `3000` |

### Prerequisites (ECR + ECS)

1. `terraform apply` in [`deploy-ecr`](../deploy-ecr); attach ECR push/pull policy to `deploy-vm`
2. `terraform apply` in [`deploy-ecs`](../deploy-ecs) with Node settings (`container_port = 3000`, `health_check_path = "/health"`, image pointing at the ECR repo). See `deploy-ecs/terraform.tfvars.example`
3. Attach `ci_deploy_policy_arn` from `deploy-ecs` to `deploy-vm` as `ecs_deploy_policy_arn`, then `terraform apply` in `deploy-vm`
4. Docker on the Jenkins agent (via [`install-jenkins`](../install-jenkins))

The app exposes `GET /health` for the ALB. Re-apply `deploy-ecs` with port **3000** before the first Node deploy.

## Jenkins CI/CD pipeline (ECR + EKS)

Declarative pipeline: [`Jenkinsfile.eks`](Jenkinsfile.eks). Same build / test / Sonar / ECR flow, then applies [`k8s/`](k8s/) to the **`deploy-eks`** cluster.

| Stage | What it does |
|-------|----------------|
| Checkout → Publish ECR | Same as ECS job |
| Deploy EKS | `aws eks update-kubeconfig` → substitute image into Deployment → `kubectl apply` → rollout status → print NLB hostname |

### Job parameters (defaults)

| Parameter | Default |
|-----------|---------|
| `AWS_REGION` | `us-east-1` |
| `ECR_REPOSITORY` | `deploy-ecr/sonarqube-node-demo` |
| `EKS_CLUSTER` | `deploy-eks-development` |
| `K8S_NAMESPACE` | `default` |

### Prerequisites (ECR + EKS)

AuthN/AuthZ use the **`deploy-vm` EC2 instance role** end-to-end.

1. **`deploy-ecr`**: `terraform apply`, then set `ecr_push_pull_policy_arn` on `deploy-vm`
2. **`deploy-eks`**: set `ci_principal_arn` to the instance role ARN, then `terraform apply`
3. **`deploy-vm`**: set `eks_deploy_policy_arn` from `deploy-eks` `ci_deploy_policy_arn`, keep ECR policy, `terraform apply`
4. **`install-jenkins`**: `ansible-playbook site.yml` (Node 20, kubectl, Docker). Re-run after policy changes if needed.

After a successful deploy, open the NLB hostname from the build log (Service port **80** → container **3000**).
