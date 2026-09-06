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
terraform -chdir=../deploy-vm output -raw ci_artifacts_bucket
```

| Value | Where to use it |
|-------|-----------------|
| SonarQube **public** IP `:9000` | Browser, GitLab `SONAR_HOST_URL` (shared GitLab.com runners) |
| SonarQube **private** IP `:9000` | Jenkins environment variable `SONAR_HOST_URL` |
| `ci_artifacts_bucket` | Jenkins environment variable `S3_BUCKET` |

### 1. Create a SonarQube token

1. Open `http://<sonarqube-public-ip>:9000` and sign in (first login is **admin** / **admin**; change it).
2. Click the avatar → **My Account** → **Security**.
3. Under **Generate Tokens**, name it `ci-sample-java-app`, type **User Token**, then **Generate**.
4. Copy the token once. You will paste the same value into GitLab and Jenkins.

### 2. GitLab — CI/CD variables

In the GitLab project: **Settings → CI/CD → Variables → Add variable**. Add each row. Mark tokens and keys **Masked** and **Hidden**; do not protect them unless every branch you scan is a protected branch.

| Key | Value | Masked | Notes |
|-----|-------|--------|-------|
| `SONAR_HOST_URL` | `http://<sonarqube-public-ip>:9000` | No | Must be reachable from the GitLab runner. Use the public IP for GitLab.com runners. |
| `SONAR_TOKEN` | token from step 1 | Yes | Required by [`.gitlab-ci.yml`](.gitlab-ci.yml) and [`sample-java-app.gitlab-ci.yml`](sample-java-app.gitlab-ci.yml) |
| `SONAR_PROJECT_KEY` | `sonarqube-java-demo` | No | Optional; this is the default |
| `AWS_ACCESS_KEY_ID` | IAM access key | Yes | Needed only if the runner has no instance profile and you publish to S3 or ECR |
| `AWS_SECRET_ACCESS_KEY` | IAM secret key | Yes | Pair with the access key |
| `AWS_DEFAULT_REGION` | `us-east-1` (or your region) | No | Same region as `deploy-vm` / `deploy-ecr` |
| `S3_BUCKET` | `terraform output -raw ci_artifacts_bucket` | No | Optional; for an S3 publish job |

IAM user or role used by GitLab needs `s3:ListBucket`, `s3:GetObject`, and `s3:PutObject` on the CI artefacts bucket (and ECR push if you use [`Jenkinsfile.sonarqube-java-demo`](Jenkinsfile.sonarqube-java-demo) style image publish).

If this repo is the workspace root, set **Settings → CI/CD → General pipelines → CI/CD configuration file** to `sample-java-app/.gitlab-ci.yml`.

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

[`Jenkinsfile`](Jenkinsfile) reads `SONAR_HOST_URL` and `S3_BUCKET` from the Jenkins environment (not job parameters).

1. Check **Environment variables**
2. **Add**:
   - Name: `SONAR_HOST_URL`, Value: `http://<sonarqube-private-ip>:9000`
   - Name: `S3_BUCKET`, Value: `terraform -chdir=../deploy-vm output -raw ci_artifacts_bucket`
3. **Save**

You can also set these on a folder or individual job instead of globally.

#### Pipeline job

1. **New Item** → name `sample-java-app` → **Pipeline** → **OK**
2. Pipeline → **Pipeline script from SCM** → your Git repo
3. Script Path: `sample-java-app/Jenkinsfile` (monorepo) or `Jenkinsfile` (app-only checkout)
4. **Save**, then **Build** (optional parameter `AWS_REGION`, default `us-east-1`)

## Jenkins CI pipeline

Declarative pipeline: [`Jenkinsfile`](Jenkinsfile).

| Stage | What it does |
|-------|----------------|
| Checkout | SCM checkout; resolves `sample-java-app/` vs app-only root; fails early if `mvn` or `aws` is missing |
| Build | `mvn -B -DskipTests compile` |
| Test | `mvn -B test` + JUnit report publish (Surefire ignores failures for training) |
| Package | `mvn -B -DskipTests package` (fat JAR for S3) |
| SonarQube Scan | `sonar-scanner` only; marked **UNSTABLE** on failure so S3 publish still runs |
| Publish artefacts | Jenkins `archiveArtifacts`, STS preflight, upload JAR/reports to S3, list destination prefix |

Use the **`deploy-vm`** output `ci_artifacts_bucket` (instance role already has `s3:PutObject`). Do not point this job at a [`deploy-s3`](../deploy-s3) bucket unless that role is granted access.

### Prerequisites (lab)

1. Apply Terraform in [`deploy-vm`](../deploy-vm) (creates VMs, CI S3 bucket, Jenkins→SonarQube:9000 SG rule).
2. Install SonarQube with [`install-sonarqube`](../install-sonarqube).
3. Install Jenkins + build tools with [`install-jenkins`](../install-jenkins) (JDK 26, Maven, sonar-scanner, plugins).
4. Add the GitLab variables and Jenkins credentials / tools from [CI credentials and tool configuration](#ci-credentials-and-tool-configuration).

Artefacts land at:

- Jenkins build archive: `target/sonarqube-java-demo-*.jar`, surefire XML
- S3: `s3://<bucket>/sample-java-app/<BUILD_NUMBER>/`

## GitLab CI pipeline

- Workspace-root project: [`.gitlab-ci.yml`](.gitlab-ci.yml) — build, test, SonarQube, GitLab artefacts / Package Registry
- App-only project: [`sample-java-app.gitlab-ci.yml`](sample-java-app.gitlab-ci.yml) — same flow, then Kaniko image push to the GitLab Container Registry

Set `SONAR_HOST_URL` and `SONAR_TOKEN` (and AWS keys if the runner is not on an AWS instance role) using the GitLab steps above.
