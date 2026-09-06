# sonarqube-java-demo

Maven Spring Boot demo for SonarQube training (intentional code-quality issues and one failing test).

## Local build and scan

```bash
mvn package
sonar-scanner
```

## CI credentials and tool configuration

Do this after Terraform (`deploy-vm`) and the Ansible installs (`install-sonarqube`, `install-jenkins`). Collect values once:

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
| `ci_artifacts_bucket` | Jenkins environment variable `S3_BUCKET` |
| App instance ID (`instance_ids.app`) | Optional Jenkins env `APP_INSTANCE_ID` for [`Jenkinsfile.deploy-app`](Jenkinsfile.deploy-app) |
| App **public** IP | Verify deploy: `http://<app-public-ip>/users/echo?q=ok` |

### 1. Create a SonarQube token

1. Open `http://<sonarqube-public-ip>:9000` and sign in (first login is **admin** / **admin**; change it).
2. Click the avatar → **My Account** → **Security**.
3. Under **Generate Tokens**, name it `ci-sample-java-app`, type **User Token**, then **Generate**.
4. Copy the token once. You will paste the same value into GitLab and Jenkins.

### 2. GitLab — CI/CD configuration file and variables

One GitLab project can only use **one** CI config file at a time (unlike multiple Jenkins jobs). Pick the pipeline under **Settings → CI/CD → General pipelines → CI/CD configuration file**:

| Pipeline (Jenkins equivalent) | Monorepo config path | App-only config path |
|-------------------------------|----------------------|----------------------|
| S3 + AI (+ Package Registry extras) | `sample-java-app/.gitlab-ci.yml` | `.gitlab-ci.yml` |
| S3 + AI + SSM Application VM deploy | `sample-java-app/.gitlab-ci.deploy-app.yml` | `.gitlab-ci.deploy-app.yml` |
| ECR publish only | `sample-java-app/.gitlab-ci.ecr.yml` | `.gitlab-ci.ecr.yml` |
| ECR + ECS deploy | `sample-java-app/.gitlab-ci.ecs.yml` | `.gitlab-ci.ecs.yml` |
| ECR + EKS deploy | `sample-java-app/.gitlab-ci.eks.yml` | `.gitlab-ci.eks.yml` |
| Kaniko → GitLab Container Registry (extra) | `sample-java-app/sample-java-app.gitlab-ci.yml` | `sample-java-app.gitlab-ci.yml` |

Then **Settings → CI/CD → Variables → Add variable**. Mark tokens and keys **Masked** and **Hidden**; do not protect them unless every branch you scan is a protected branch.

| Key | Value | Masked | Required for |
|-----|-------|--------|--------------|
| `SONAR_HOST_URL` | `http://<sonarqube-public-ip>:9000` | No | All Sonar + AI sonar jobs (use **public** IP for GitLab.com runners; private IP OK for a self-hosted runner in the lab VPC) |
| `SONAR_TOKEN` | token from step 1 | Yes | All Sonar + AI sonar jobs |
| `SONAR_PROJECT_KEY` | `sonarqube-java-demo` | No | Optional; this is the default |
| `S3_BUCKET` | `terraform -chdir=deploy-vm output -raw ci_artifacts_bucket` | No | S3 and SSM pipelines |
| `APP_INSTANCE_ID` | `instance_ids.app` from `deploy-vm` | No | Optional for SSM; else discovers EC2 tag `Role=app` |
| `AWS_DEFAULT_REGION` / `AWS_REGION` | `us-east-1` | No | AWS jobs (YAML default is `us-east-1`) |
| `AWS_ACCESS_KEY_ID` | IAM access key | Yes | Only if the runner has **no** instance profile |
| `AWS_SECRET_ACCESS_KEY` | IAM secret key | Yes | Pair with the access key |
| `BEDROCK_MODEL_ID` | `us.amazon.nova-lite-v1:0` | No | Optional AI stages |
| `BEDROCK_GUARDRAIL_ID` | from `deploy-bedrock` | No | Optional |
| `BEDROCK_GUARDRAIL_VERSION` | `DRAFT` | No | Optional |
| `ECR_REPOSITORY` | `deploy-ecr/sonarqube-java-demo` | No | Optional override for ECR/ECS/EKS |
| `ECS_CLUSTER` / `ECS_SERVICE` / `ECS_TASK_FAMILY` / `ECS_CONTAINER_NAME` / `ECS_CONTAINER_PORT` | YAML defaults (`8080`) | No | Optional ECS overrides |
| `EKS_CLUSTER` / `K8S_NAMESPACE` | YAML defaults | No | Optional EKS overrides |

GitLab built-ins (do **not** create): `CI_JOB_TOKEN`, `CI_API_V4_URL`, `CI_PROJECT_ID`, `CI_REGISTRY_*`, `CI_PIPELINE_IID` (used as image/S3 build number).

**AWS identity for the runner (choose one):**

- **Preferred for this lab:** self-hosted GitLab runner on the Jenkins EC2 — the `deploy-vm` instance profile already has S3 / Bedrock / ECR / ECS / EKS / SSM when those Terraform policies are attached.
- **GitLab.com shared runners:** create an IAM user, attach the same policies (`bedrock_invoke`, `ecr_push_pull`, `ecs_deploy`, `eks_deploy`, S3, SSM), store keys as masked variables. For EKS, set `ci_principal_arn` (or an extra access entry) in `deploy-eks` to that user’s ARN.

There is **no** GitLab equivalent of Jenkins credential IDs `sonarqube-token` / `aws-ci` — use CI/CD variables only.

### 3. Jenkins — credentials, tools, and environment

Open `http://<jenkins-public-ip>:8080`.

#### Credentials (Manage Jenkins → Credentials → System → Global credentials → Add credentials)

**SonarQube token**

1. Kind: **Secret text**
2. Secret: paste the SonarQube token
3. ID: `sonarqube-token` (must match this ID; [`Jenkinsfile`](Jenkinsfile) binds `credentials('sonarqube-token')`)
4. Description: `SonarQube CI token`
5. **Create**

**AWS credentials** (optional on the lab Jenkins EC2 — that host already uses the instance profile from `deploy-vm`. Add these if Jenkins runs elsewhere, or you want an explicit key pair.)

1. Kind: **AWS Credentials** (plugin `aws-credentials`, installed by `install-jenkins`)
2. ID: `aws-ci`
3. Access Key ID / Secret Access Key: IAM user that can write the CI artefacts bucket (and ECR if you publish images)
4. Description: `AWS CI for sample-java-app`
5. **Create**

#### Tools (Manage Jenkins → Tools)

These match the paths installed by [`install-jenkins`](../install-jenkins). Uncheck **Install automatically** and point at the local installs.

| Tool | Name to enter | Home / path |
|------|---------------|-------------|
| JDK | `jdk-26` | `/usr/lib/jvm/java-26-amazon-corretto.x86_64` |
| Maven | `maven-3.9` | `/opt/maven` |
| SonarQube Scanner | `sonar-scanner` | `/opt/sonar-scanner` |

Click **Save** at the bottom.

The default [`Jenkinsfile`](Jenkinsfile) uses `PATH` (`/opt/maven/bin`, `/opt/sonar-scanner/bin`) rather than `tool` steps. Configuring Tools still lets you select them in freestyle jobs and in [`Jenkinsfile.sonarqube-java-demo`](Jenkinsfile.sonarqube-java-demo) if you switch to `tool` bindings.

#### Environment variables (Manage Jenkins → System → Global properties)

[`Jenkinsfile`](Jenkinsfile) and [`Jenkinsfile.deploy-app`](Jenkinsfile.deploy-app) read `SONAR_HOST_URL` and `S3_BUCKET` from the Jenkins environment (not job parameters).

1. Check **Environment variables**
2. **Add**:
   - Name: `SONAR_HOST_URL`, Value: `http://<sonarqube-private-ip>:9000`
   - Name: `S3_BUCKET`, Value: `terraform -chdir=../deploy-vm output -raw ci_artifacts_bucket`
   - Name: `APP_INSTANCE_ID` (optional), Value: `terraform -chdir=../deploy-vm output -json instance_ids` → `app`. If unset, [`Jenkinsfile.deploy-app`](Jenkinsfile.deploy-app) discovers a running EC2 with tag `Role=app`.
   - Name: `BEDROCK_MODEL_ID` (optional), Value: `us.amazon.nova-lite-v1:0` — advisory AI stages ([`ci/ai`](../ci/ai/README.md)); requires `deploy-bedrock` + `bedrock_invoke_policy_arn` on `deploy-vm`
   - Name: `BEDROCK_GUARDRAIL_ID` (optional) — when Guardrail is enabled in `deploy-bedrock`
3. **Save**

You can also set these on a folder or individual job instead of globally.

#### Pipeline job

Preferred: create all sample jobs and the **Java** / **Node** views with sibling [`jenkins-pipeline`](../jenkins-pipeline) (`cp jobs.env.example jobs.env` → `./create-jobs.sh`).

Or by hand:

1. **New Item** → name `sample-java-app` → **Pipeline** → **OK**
2. Pipeline → **Pipeline script from SCM** → your Git repo
3. Script Path: `sample-java-app/Jenkinsfile` (monorepo) or `Jenkinsfile` (app-only checkout)
4. **Save**, then **Build** (optional parameter `AWS_REGION`, default `us-east-1`)

For build + Sonar + S3 + deploy to the Application VM, create a job with Script Path `sample-java-app/Jenkinsfile.deploy-app` (see [Jenkins CI + Application VM deploy](#jenkins-ci--application-vm-deploy)).

For ECR + ECS deploy, create a job with Script Path `sample-java-app/Jenkinsfile.ecs` (see [Jenkins CI/CD pipeline (ECR + ECS)](#jenkins-cicd-pipeline-ecr--ecs)).

For ECR + EKS deploy, create a job with Script Path `sample-java-app/Jenkinsfile.eks` (see [Jenkins CI/CD pipeline (ECR + EKS)](#jenkins-cicd-pipeline-ecr--eks)).

## Jenkins CI pipeline

Declarative pipeline: [`Jenkinsfile`](Jenkinsfile).

| Stage | What it does |
|-------|----------------|
| Checkout | SCM checkout; resolves `sample-java-app/` vs app-only root; resolves `ci/ai/ai-review.sh`; fails early if `mvn` or `aws` is missing |
| Build | `mvn -B -DskipTests compile` |
| Test | `mvn -B test` + JUnit report publish (Surefire ignores failures for training) |
| AI Test Review | Bedrock explains JUnit results (advisory; never fails the job) |
| Package | `mvn -B -DskipTests package` (fat JAR for S3) |
| SonarQube Scan | `sonar-scanner` only; marked **UNSTABLE** on failure so S3 publish still runs |
| AI Quality Review | Bedrock explains unresolved Sonar issues (advisory) |
| AI Change Risk | Bedrock summarizes recent commits / diff (advisory; does not gate deploy) |
| Publish artefacts | Jenkins `archiveArtifacts`, STS preflight, upload JAR/reports/`ai-review` to S3, list destination prefix |

Use the **`deploy-vm`** output `ci_artifacts_bucket` (instance role already has `s3:PutObject`). Do not point this job at a [`deploy-s3`](../deploy-s3) bucket unless that role is granted access.

### Jenkins CI + Application VM deploy

Declarative pipeline: [`Jenkinsfile.deploy-app`](Jenkinsfile.deploy-app). Same stages as above, then deploys via SSM.

| Stage | What it does |
|-------|----------------|
| Checkout → Publish artefacts | Same as [`Jenkinsfile`](Jenkinsfile) (including advisory AI stages) |
| Deploy to Application VM | Upload [`ci/deploy-app.sh`](ci/deploy-app.sh) to S3; resolve app EC2 (`APP_INSTANCE_ID` or tag `Role=app`); `ssm send-command` so the VM pulls the JAR, installs Corretto 26 if needed, writes a systemd unit on port **80**, restarts, and health-checks `http://127.0.0.1/users/echo?q=ok`; writes SSM diagnostics under `ai-review/` |
| post failure | **AI Deploy RCA** — Bedrock explains failed SSM deploy from diagnostics (advisory) |

Verify from your allowed CIDR:

```bash
curl "http://<app-public-ip>/users/echo?q=ok"
```

Requires `terraform apply` in [`deploy-vm`](../deploy-vm) so the shared instance role has the SSM deploy IAM (`ci_ssm_deploy.tf`).

### Prerequisites (lab)

1. Apply Terraform in [`deploy-vm`](../deploy-vm) (creates VMs, CI S3 bucket, Jenkins→SonarQube:9000 SG rule, SSM deploy IAM).
2. Install SonarQube with [`install-sonarqube`](../install-sonarqube).
3. Install Jenkins + build tools with [`install-jenkins`](../install-jenkins) (JDK 26, Maven, sonar-scanner, plugins).
4. Add the GitLab variables and Jenkins credentials / tools from [CI credentials and tool configuration](#ci-credentials-and-tool-configuration).

Artefacts land at:

- Jenkins build archive: `target/sonarqube-java-demo-*.jar`, surefire XML
- S3: `s3://<bucket>/sample-java-app/<BUILD_NUMBER>/`
- App VM (deploy pipeline): `/opt/sample-java-app/app.jar`, systemd unit `sample-java-app` on port 80

## Jenkins CI/CD pipeline (ECR + ECS)

Declarative pipeline: [`Jenkinsfile.ecs`](Jenkinsfile.ecs). Builds with Docker Maven, scans with SonarQube, pushes the image to **`deploy-ecr/sonarqube-java-demo`**, then registers a new ECS task definition and updates the Fargate service.

| Stage | What it does |
|-------|----------------|
| Checkout | SCM checkout; fails early if `docker`, `aws`, or `python3` is missing; resolves `ci/ai/ai-review.sh` |
| Build | `mvn -B -DskipTests package` via `maven:3.9-eclipse-temurin-26` |
| Test | `mvn -B test jacoco:report` + JUnit / JaCoCo artefacts |
| AI Test Review | Bedrock explains JUnit results (advisory) |
| SonarQube | `mvn sonar:sonar` (`SONAR_HOST_URL` + credential `sonarqube-token`) |
| AI Quality Review / AI Change Risk | Bedrock advisory Sonar explanation and change summary |
| Publish ECR | `docker build` / push `${BUILD_NUMBER}` and `latest` to ECR |
| Deploy ECS | Rewrite task definition image + port → `register-task-definition` → `update-service` → poll until PRIMARY `COMPLETED` (fails with diagnostics on timeout) |
| post failure | **AI Deploy RCA** from ECS diagnostics (advisory) |

### Job setup

1. **New Item** → Pipeline → Script Path `sample-java-app/Jenkinsfile.ecs`
2. Same `sonarqube-token` credential and `SONAR_HOST_URL` as the S3 job
3. Optional build parameters (defaults match Terraform naming):

| Parameter | Default |
|-----------|---------|
| `AWS_REGION` | `us-east-1` |
| `ECR_REPOSITORY` | `deploy-ecr/sonarqube-java-demo` |
| `ECS_CLUSTER` | `deploy-ecs-development-cluster` |
| `ECS_SERVICE` | `app` |
| `ECS_TASK_FAMILY` | `deploy-ecs-development-app` |
| `ECS_CONTAINER_NAME` | `app` |
| `ECS_CONTAINER_PORT` | `8080` |

### Prerequisites (ECR + ECS)

1. Apply [`deploy-ecr`](../deploy-ecr) and attach `push_pull_policy_arn` to `deploy-vm` as `ecr_push_pull_policy_arn`.
2. Apply [`deploy-ecs`](../deploy-ecs) with the Java service settings (`container_port = 8080`, `health_check_path = "/health"`, `image` pointing at the ECR repo). See `deploy-ecs/terraform.tfvars.example` (open demo uses `allowed_ingress_cidr = "0.0.0.0/0"`).
3. Attach `ci_deploy_policy_arn` from `deploy-ecs` to `deploy-vm` as `ecs_deploy_policy_arn`, then `terraform apply` in `deploy-vm`.
4. Re-run [`install-jenkins`](../install-jenkins) so the agent has **Docker**, **python3**, and the `jenkins` user in the `docker` group.

The app exposes `GET /health` for the ALB health check. Re-apply `deploy-ecs` with port **8080** before the first deploy; changing only the image in CI is not enough if the target group is still on port 80.

## Jenkins CI/CD pipeline (ECR + EKS)

Declarative pipeline: [`Jenkinsfile.eks`](Jenkinsfile.eks). Same build / test / Sonar / ECR flow as [`Jenkinsfile.ecs`](Jenkinsfile.ecs), then applies Kubernetes manifests under [`k8s/`](k8s/) to the **`deploy-eks`** cluster (internet-facing NLB Service).

| Stage | What it does |
|-------|----------------|
| Checkout | SCM checkout; fails early if `docker` or `aws` is missing; uses PATH kubectl from `install-jenkins`; resolves AI script |
| Build | `mvn -B -DskipTests package` via `maven:3.9-eclipse-temurin-26` |
| Test | `mvn -B test jacoco:report` + JUnit / JaCoCo artefacts |
| AI Test Review | Bedrock explains JUnit results (advisory) |
| SonarQube | `mvn sonar:sonar` (`SONAR_HOST_URL` + credential `sonarqube-token`) |
| AI Quality Review / AI Change Risk | Bedrock advisory Sonar explanation and change summary |
| Publish ECR | `docker build` / push `${BUILD_NUMBER}` and `latest` to ECR |
| Deploy EKS | `aws eks update-kubeconfig` (instance role) → substitute image into Deployment → `kubectl apply` → rollout status → print NLB hostname |
| post failure | **AI Deploy RCA** from EKS rollout diagnostics (advisory) |

### Job setup

1. **New Item** → Pipeline → Script Path `sample-java-app/Jenkinsfile.eks`
2. Same `sonarqube-token` credential and `SONAR_HOST_URL` as the other jobs (no AWS access keys; the Jenkins EC2 instance profile authenticates)
3. Optional build parameters (defaults match Terraform naming):

| Parameter | Default |
|-----------|---------|
| `AWS_REGION` | `us-east-1` |
| `ECR_REPOSITORY` | `deploy-ecr/sonarqube-java-demo` |
| `EKS_CLUSTER` | `deploy-eks-development` |
| `K8S_NAMESPACE` | `default` |

### Prerequisites (ECR + EKS) — Terraform AuthN/AuthZ only

AuthN and AuthZ use the **`deploy-vm` EC2 instance role** end-to-end. Do not create an IAM User, access keys, or run `aws eks create-access-entry` by hand.

Apply order:

1. **`deploy-ecr`**: `terraform apply`, then set `ecr_push_pull_policy_arn` on `deploy-vm` from `push_pull_policy_arn`.
2. **`deploy-eks`**: set Terraform AuthZ for the instance role (public API defaults to `0.0.0.0/0` for demo labs; add `additional_api_cidrs` only if you narrow `allowed_api_cidr`):

```hcl
ci_principal_arn = "<terraform -chdir=../deploy-vm output -raw instance_role_arn>"
# additional_api_cidrs = ["<jenkins-public-ip>/32"]  # only if allowed_api_cidr is narrowed
```

   `terraform apply` creates the EKS access entry and associates `AmazonEKSClusterAdminPolicy`.
3. **`deploy-vm`**: set `eks_deploy_policy_arn` from `terraform -chdir=../deploy-eks output -raw ci_deploy_policy_arn`, keep `ecr_push_pull_policy_arn`, then `terraform apply`.
4. **`install-jenkins`**: re-run `ansible-playbook site.yml` so **kubectl**, **Docker**, and **python3** are on the agent (`jenkins` is in the `docker` group).

The pipeline calls `aws eks update-kubeconfig` with the instance profile; kubectl then uses that identity.

After a successful deploy, open the NLB hostname printed in the build log (Service port **80** → container **8080**). The app exposes `GET /health` (same as ECS); the Service probes use TCP on 8080.

## GitLab CI pipelines

Each file mirrors one Jenkinsfile. Set the **CI/CD configuration file** path as in [GitLab — CI/CD configuration file and variables](#2-gitlab--cicd-configuration-file-and-variables).

| Config file | Jenkins equivalent | Stages |
|-------------|-------------------|--------|
| [`.gitlab-ci.yml`](.gitlab-ci.yml) | [`Jenkinsfile`](Jenkinsfile) | Build → test → AI tests → package → Sonar → AI review → publish (S3 **and** GitLab artefacts / Package Registry) |
| [`.gitlab-ci.deploy-app.yml`](.gitlab-ci.deploy-app.yml) | [`Jenkinsfile.deploy-app`](Jenkinsfile.deploy-app) | Same as S3 + SSM deploy + AI Deploy RCA on failure |
| [`.gitlab-ci.ecr.yml`](.gitlab-ci.ecr.yml) | [`Jenkinsfile.sonarqube-java-demo`](Jenkinsfile.sonarqube-java-demo) | Build → test → AI → Sonar → AI → Kaniko → ECR |
| [`.gitlab-ci.ecs.yml`](.gitlab-ci.ecs.yml) | [`Jenkinsfile.ecs`](Jenkinsfile.ecs) | ECR flow + ECS rolling deploy + AI Deploy RCA on failure |
| [`.gitlab-ci.eks.yml`](.gitlab-ci.eks.yml) | [`Jenkinsfile.eks`](Jenkinsfile.eks) | ECR flow + EKS kubectl deploy + AI Deploy RCA on failure |
| [`sample-java-app.gitlab-ci.yml`](sample-java-app.gitlab-ci.yml) | *(GitLab-only extra)* | Build → test → Sonar → Kaniko → **GitLab Container Registry** |

Parity notes:

- Advisory AI / Sonar failures use `allow_failure: true` (same idea as Jenkins `catchError` UNSTABLE).
- S3 prefix and image tags use `CI_PIPELINE_IID` instead of Jenkins `BUILD_NUMBER`.
- ECR publish uses **Kaniko** (no privileged Docker needed on shared runners).
- Reuses [`ci/ai/ai-review.sh`](../ci/ai/ai-review.sh) and [`ci/deploy-app.sh`](ci/deploy-app.sh).

Lab infra prerequisites match the Jenkins sections above (`deploy-vm`, SonarQube, optional `deploy-bedrock` / `deploy-ecr` / `deploy-ecs` / `deploy-eks`). Attach IAM policies to the **GitLab runner identity**, not only the Jenkins instance role, when using access keys.
