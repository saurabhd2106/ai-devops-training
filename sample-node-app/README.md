# sonarqube-node-demo

Express demo for SonarQube training (intentional code-quality issues and one failing Jest test).

Local development only (not a deploy path): `npm install` | `npm start` | `npm test`.

All lab provisioning and CI/CD runs through **Terraform**, **Ansible**, a **Jenkinsfile**, or **GitLab CI** YAML.

## Execution contract

| Mechanism | Owns | How to run |
|-----------|------|------------|
| **Terraform** | AWS resources (VMs, S3 artefacts bucket, ECR, ECS, EKS, IAM) | `terraform apply` in `deploy-vm`, `deploy-ecr`, `deploy-ecs`, `deploy-eks` |
| **Ansible** | Tools on the Jenkins EC2 (Node 20, sonar-scanner, kubectl, …) | `ansible-playbook site.yml` in [`install-jenkins`](../install-jenkins) |
| **Jenkinsfile** | Build, test, SonarQube, publish, and deploy | Jenkins **Pipeline script from SCM** → Script Path below |
| **GitLab CI** | Same flows as Jenkinsfiles | **Settings → CI/CD → CI/CD configuration file** → path below |

Supporting files (`Dockerfile`, `k8s/`, `ci/deploy-app.sh`) are consumed by Jenkinsfiles and GitLab CI. Do not run them by hand.

The shared Application VM (`Role=app`) and the single ECS `app` service can host **either** the Java sample **or** this Node sample at a time — not both.

## CI credentials and tool configuration

Do this after Terraform (`deploy-vm`) and Ansible (`install-sonarqube`, `install-jenkins`). Collect values once:

```bash
terraform -chdir=../deploy-vm output -json public_ips
terraform -chdir=../deploy-vm output -json private_ips
terraform -chdir=../deploy-vm output -json instance_ids
terraform -chdir=../deploy-vm output -raw ci_artifacts_bucket
```

| Value | Where to use it |
|-------|-----------------|
| SonarQube **public** IP `:9000` | Browser, GitLab `SONAR_HOST_URL` (shared GitLab.com runners) |
| SonarQube **private** IP `:9000` | Jenkins environment variable `SONAR_HOST_URL` |
| `ci_artifacts_bucket` | Jenkins / GitLab `S3_BUCKET` |
| App instance ID (`instance_ids.app`) | Optional Jenkins/GitLab `APP_INSTANCE_ID` for deploy-app pipelines |
| App **public** IP | Verify VM deploy: `http://<app-public-ip>/health` |

### 1. Create a SonarQube token

1. Open `http://<sonarqube-public-ip>:9000` and sign in.
2. Avatar → **My Account** → **Security** → generate a **User Token** (e.g. `ci-sample-node-app`).
3. Use the same token for Jenkins credential ID `sonarqube-token` and GitLab variable `SONAR_TOKEN`.

### 2. GitLab — CI/CD configuration file and variables

One GitLab project can only use **one** CI config file at a time. Pick the pipeline under **Settings → CI/CD → General pipelines → CI/CD configuration file**:

| Pipeline (Jenkins equivalent) | Monorepo config path | App-only config path |
|-------------------------------|----------------------|----------------------|
| S3 + AI | `sample-node-app/.gitlab-ci.yml` | `.gitlab-ci.yml` |
| S3 + AI + SSM Application VM deploy | `sample-node-app/.gitlab-ci.deploy-app.yml` | `.gitlab-ci.deploy-app.yml` |
| ECR publish only | `sample-node-app/.gitlab-ci.ecr.yml` | `.gitlab-ci.ecr.yml` |
| ECR + ECS deploy | `sample-node-app/.gitlab-ci.ecs.yml` | `.gitlab-ci.ecs.yml` |
| ECR + EKS deploy | `sample-node-app/.gitlab-ci.eks.yml` | `.gitlab-ci.eks.yml` |

Then **Settings → CI/CD → Variables → Add variable**. Mark tokens and keys **Masked** and **Hidden**; do not protect them unless every branch you scan is a protected branch.

| Key | Value | Masked | Required for |
|-----|-------|--------|--------------|
| `SONAR_HOST_URL` | `http://<sonarqube-public-ip>:9000` | No | All Sonar + AI sonar jobs (public IP for GitLab.com runners) |
| `SONAR_TOKEN` | token from step 1 | Yes | All Sonar + AI sonar jobs |
| `SONAR_PROJECT_KEY` | `sonarqube-node-demo` | No | Optional; this is the default |
| `S3_BUCKET` | `terraform -chdir=deploy-vm output -raw ci_artifacts_bucket` | No | S3 and SSM pipelines |
| `APP_INSTANCE_ID` | `instance_ids.app` from `deploy-vm` | No | Optional for SSM; else discovers EC2 tag `Role=app` |
| `AWS_DEFAULT_REGION` / `AWS_REGION` | `us-east-1` | No | AWS jobs |
| `AWS_ACCESS_KEY_ID` | IAM access key | Yes | Only if the runner has **no** instance profile |
| `AWS_SECRET_ACCESS_KEY` | IAM secret key | Yes | Pair with the access key |
| `BEDROCK_MODEL_ID` | `us.amazon.nova-lite-v1:0` | No | Optional AI stages |
| `BEDROCK_GUARDRAIL_ID` | from `deploy-bedrock` | No | Optional |
| `BEDROCK_GUARDRAIL_VERSION` | `DRAFT` | No | Optional |
| `ECR_REPOSITORY` | `deploy-ecr/sonarqube-node-demo` | No | Optional override for ECR/ECS/EKS |
| `ECS_CLUSTER` / `ECS_SERVICE` / `ECS_TASK_FAMILY` / `ECS_CONTAINER_NAME` / `ECS_CONTAINER_PORT` | YAML defaults (`3000`) | No | Optional ECS overrides |
| `EKS_CLUSTER` / `K8S_NAMESPACE` | YAML defaults | No | Optional EKS overrides |

GitLab built-ins (do **not** create): `CI_PIPELINE_IID` (used as image/S3 build number), `CI_COMMIT_*`.

**AWS identity for the runner (choose one):**

- **Preferred for this lab:** self-hosted GitLab runner on the Jenkins EC2 — the `deploy-vm` instance profile already has S3 / Bedrock / ECR / ECS / EKS / SSM when those Terraform policies are attached.
- **GitLab.com shared runners:** create an IAM user, attach the same policies, store keys as masked variables. For EKS, set `ci_principal_arn` in `deploy-eks` to that user’s ARN.

There is **no** GitLab equivalent of Jenkins credential IDs `sonarqube-token` / `aws-ci` — use CI/CD variables only.

### 3. Jenkins — credentials, tools, and environment

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
   - `BEDROCK_MODEL_ID` (optional) = `us.amazon.nova-lite-v1:0` for advisory AI stages ([`ci/ai`](../ci/ai/README.md)); requires `deploy-bedrock` + `bedrock_invoke_policy_arn` on `deploy-vm`
   - `BEDROCK_GUARDRAIL_ID` (optional) when Guardrail is enabled in `deploy-bedrock`
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
| Checkout | SCM checkout; resolves `sample-node-app/` vs app-only root; resolves `ci/ai/ai-review.sh`; fails early if `node`, `npm`, or `aws` is missing |
| Build | `npm ci` |
| Test | `npm run test:ci` (intentional failing test → **UNSTABLE**) + JUnit / coverage artefacts |
| AI Test Review | Bedrock explains Jest/JUnit results (advisory; never fails the job) |
| Package | Production `npm ci --omit=dev` + tarball `sonarqube-node-demo-1.0.0.tgz` |
| SonarQube Scan | `sonar-scanner`; **UNSTABLE** on failure so S3 publish still runs |
| AI Quality Review | Bedrock explains unresolved Sonar issues (advisory) |
| AI Change Risk | Bedrock summarizes recent commits / diff (advisory) |
| Publish artefacts | Jenkins archive + upload tarball/junit/`ai-review` to S3 |

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
| Checkout → Publish artefacts | Same as [`Jenkinsfile`](Jenkinsfile) (including advisory AI stages) |
| Deploy to Application VM | Upload [`ci/deploy-app.sh`](ci/deploy-app.sh) to S3; resolve app EC2 (`APP_INSTANCE_ID` or tag `Role=app`); SSM runs the script so the VM pulls the tarball, installs Node 20 if needed, writes systemd unit `sample-node-app` on port **80**, health-checks `/health`; writes SSM diagnostics under `ai-review/` |
| post failure | **AI Deploy RCA** — Bedrock explains failed SSM deploy (advisory) |

Verify: `http://<app-public-ip>/health`

Requires `deploy-vm` SSM deploy IAM (`ci_ssm_deploy.tf`). Do not run `deploy-app.sh` outside this Jenkinsfile.

## Jenkins CI/CD pipeline (ECR only)

Declarative pipeline: [`Jenkinsfile.sonarqube-node-demo`](Jenkinsfile.sonarqube-node-demo).

| Stage | What it does |
|-------|----------------|
| Checkout | Fails early if `docker` or `aws` is missing; resolves AI script |
| Build / Test | `node:20` Docker image + Jest (**UNSTABLE** on intentional failure) |
| AI Test Review | Bedrock explains Jest results (advisory) |
| SonarQube | `sonarsource/sonar-scanner-cli` |
| AI Quality Review / AI Change Risk | Bedrock advisory Sonar explanation and change summary |
| Publish | `docker build` / push `${BUILD_NUMBER}` and `latest` to `deploy-ecr/sonarqube-node-demo` |

### Prerequisites

1. `terraform apply` in [`deploy-ecr`](../deploy-ecr) (includes `sonarqube-node-demo` repo)
2. Attach `push_pull_policy_arn` to `deploy-vm` as `ecr_push_pull_policy_arn`, then `terraform apply` in `deploy-vm`
3. Docker on the Jenkins agent (installed by [`install-jenkins`](../install-jenkins) when `jenkins_install_docker` is true)

## Jenkins CI/CD pipeline (ECR + ECS)

Declarative pipeline: [`Jenkinsfile.ecs`](Jenkinsfile.ecs).

| Stage | What it does |
|-------|----------------|
| Checkout → Publish ECR | Same as ECR-only job (including advisory AI stages) |
| Deploy ECS | Rewrite task definition image/port → `register-task-definition` → `update-service` → wait for stable |
| post failure | **AI Deploy RCA** from ECS diagnostics (advisory) |

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
| Checkout → Publish ECR | Same as ECS job (including advisory AI stages) |
| Deploy EKS | `aws eks update-kubeconfig` → substitute image into Deployment → `kubectl apply` → rollout status → print NLB hostname |
| post failure | **AI Deploy RCA** from EKS rollout diagnostics (advisory) |

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

## GitLab CI pipelines

Each file mirrors one Jenkinsfile. Set the **CI/CD configuration file** path as in [GitLab — CI/CD configuration file and variables](#2-gitlab--cicd-configuration-file-and-variables).

| Config file | Jenkins equivalent | Stages |
|-------------|-------------------|--------|
| [`.gitlab-ci.yml`](.gitlab-ci.yml) | [`Jenkinsfile`](Jenkinsfile) | Build → test → AI tests → package → Sonar → AI review → S3 publish |
| [`.gitlab-ci.deploy-app.yml`](.gitlab-ci.deploy-app.yml) | [`Jenkinsfile.deploy-app`](Jenkinsfile.deploy-app) | Same as S3 + SSM deploy + AI Deploy RCA on failure |
| [`.gitlab-ci.ecr.yml`](.gitlab-ci.ecr.yml) | [`Jenkinsfile.sonarqube-node-demo`](Jenkinsfile.sonarqube-node-demo) | Build → test → AI → Sonar → AI → Kaniko → ECR |
| [`.gitlab-ci.ecs.yml`](.gitlab-ci.ecs.yml) | [`Jenkinsfile.ecs`](Jenkinsfile.ecs) | ECR flow + ECS rolling deploy + AI Deploy RCA on failure |
| [`.gitlab-ci.eks.yml`](.gitlab-ci.eks.yml) | [`Jenkinsfile.eks`](Jenkinsfile.eks) | ECR flow + EKS kubectl deploy + AI Deploy RCA on failure |

Parity notes:

- Test / Sonar / AI failures use `allow_failure: true` (same idea as Jenkins `catchError` UNSTABLE).
- S3 prefix and image tags use `CI_PIPELINE_IID` instead of Jenkins `BUILD_NUMBER`.
- ECR publish uses **Kaniko** (no privileged Docker needed on shared runners).
- Reuses [`ci/ai/ai-review.sh`](../ci/ai/ai-review.sh) and [`ci/deploy-app.sh`](ci/deploy-app.sh).

Lab infra prerequisites match the Jenkins sections above. Attach IAM policies to the **GitLab runner identity** when using access keys.
