# install-jenkins — Ansible Jenkins LTS on Amazon Linux 2023

Installs **Jenkins LTS** on an existing EC2 instance provisioned by [`deploy-vm`](../deploy-vm/README.md) (Amazon Linux 2023, port **8080**, user `ec2-user`), plus CI build tools for [`sample-java-app`](../sample-java-app) and [`sample-node-app`](../sample-node-app).

This project does **not** create AWS resources. Run it after `terraform apply` in `deploy-vm` (or against any matching AL2023 host).

## What it installs

| Component | Detail |
|-----------|--------|
| Java (Jenkins JVM) | Amazon Corretto **21** (`java-21-amazon-corretto`), pinned via systemd drop-in |
| Java (builds) | Amazon Corretto **26** JDK (`java-26-amazon-corretto-devel`) for Maven/sample-java-app |
| Node.js (builds) | Amazon Linux **nodejs20** (`node` / `npm` on PATH) for sample-node-app |
| Maven | Apache Maven 3.9.x under `/opt/maven` |
| SonarScanner | SonarScanner CLI under `/opt/sonar-scanner` |
| kubectl | Kubernetes CLI **1.36.x** at `/usr/local/bin/kubectl` (for EKS Jenkinsfiles) |
| Docker | Docker Engine on AL2023; `jenkins` user in the `docker` group (for ECR / ECS / EKS image builds) |
| python3 | Used by ECS Jenkinsfiles to rewrite task definitions |
| AWS CLI | `awscli-2` (S3 artefact upload via instance profile) |
| git / unzip / tar / fontconfig | Build and extract helpers |
| Jenkins | LTS from `pkg.jenkins.io/rpm-stable` |
| Plugins | From [`roles/jenkins/files/plugins.txt`](roles/jenkins/files/plugins.txt) via plugin manager CLI |
| Service | `systemd` unit `jenkins`, listening on port **8080** |

After install, the playbook prints the initial admin password from `/var/lib/jenkins/secrets/initialAdminPassword`.

## Prerequisites

- [ansible-core](https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html) `>= 2.15`
- SSH access to the Jenkins EC2 (same private key used with `deploy-vm`)
- A running Jenkins-role VM with security group allowing TCP **22** and **8080** from your IP (default `deploy-vm` layout)
- For sample-java-app / sample-node-app pipelines: SonarQube installed and reachable from Jenkins (deploy-vm adds SG rule TCP 9000 from Jenkins → SonarQube)

```bash
# Optional: confirm ansible is available
ansible --version
```

## Quick start

```bash
cd install-jenkins

cp inventory.ini.example inventory.ini
# Set the Jenkins public IP and private key path in inventory.ini
```

Fill the host from Terraform:

```bash
terraform -chdir=../deploy-vm output -json public_ips
# Use the "jenkins" value as the inventory host
```

Example `inventory.ini`:

```ini
[jenkins]
203.0.113.10 ansible_user=ec2-user ansible_ssh_private_key_file=~/.ssh/id_ed25519
```

Run the playbook:

```bash
ansible-playbook site.yml
```

Optional full package upgrade before install (slower):

```bash
ansible-playbook site.yml -e jenkins_update_packages=true
```

## After install

1. Open `http://<jenkins-public-ip>:8080` (from the CIDR allowed in `deploy-vm`).
2. Paste the initial admin password printed by the playbook (or run `sudo cat /var/lib/jenkins/secrets/initialAdminPassword` on the host).
3. Complete the Jenkins setup wizard (you can skip suggested plugins; pipeline plugins are already installed).
4. Add AWS credentials, SonarQube details, and global tools (full click-path is in [`sample-java-app/README.md`](../sample-java-app/README.md#3-jenkins--credentials-tools-and-environment) and [`sample-node-app/README.md`](../sample-node-app/README.md)):

   | Where | What to add |
   |-------|-------------|
   | **Manage Jenkins → Credentials** | Secret text ID **`sonarqube-token`** (token from SonarQube → My Account → Security). Optional: Kind **AWS Credentials**, ID **`aws-ci`**, if Jenkins is not using the `deploy-vm` instance profile. |
   | **Manage Jenkins → Tools** | JDK `jdk-26` → `/usr/lib/jvm/java-26-amazon-corretto.x86_64`. Maven `maven-3.9` → `/opt/maven`. SonarQube Scanner `sonar-scanner` → `/opt/sonar-scanner`. Uncheck **Install automatically**. Node 20 is on PATH via `nodejs20` (no Jenkins tool entry required). |
   | **Manage Jenkins → System → Global properties** | Env **`SONAR_HOST_URL`** = `http://<sonarqube-private-ip>:9000`. Env **`S3_BUCKET`** = `terraform -chdir=../deploy-vm output -raw ci_artifacts_bucket`. Optional: **`APP_INSTANCE_ID`** for Application VM deploy. Optional for advisory AI stages ([`ci/ai`](../ci/ai/README.md)): **`BEDROCK_MODEL_ID`** = `us.amazon.nova-lite-v1:0` (after `deploy-bedrock` + `bedrock_invoke_policy_arn` on `deploy-vm`); **`BEDROCK_GUARDRAIL_ID`** if Guardrail enabled. |
   | Job | **New Item** → Pipeline → **Pipeline script from SCM**, or run sibling [`jenkins-pipeline`](../jenkins-pipeline) (`./create-jobs.sh`) to create all Java/Node jobs and **Java** / **Node** views via the REST API. Script Paths: `sample-java-app/Jenkinsfile` or `sample-node-app/Jenkinsfile` (S3), matching `Jenkinsfile.deploy-app` (SSM to app VM), `Jenkinsfile.ecs` (ECR + ECS), or `Jenkinsfile.eks` (ECR + EKS) |

## Variables

Defaults live in [`roles/jenkins/defaults/main.yml`](roles/jenkins/defaults/main.yml). Override in [`group_vars/all.yml`](group_vars/all.yml) or with `-e`.

| Name | Default | Description |
|------|---------|-------------|
| `jenkins_http_port` | `8080` | Port to wait for after start (must match SG) |
| `jenkins_java_package` | `java-21-amazon-corretto` | Jenkins JVM package |
| `jenkins_java_home` | `/usr/lib/jvm/java-21-amazon-corretto.x86_64` | Pinned Jenkins `JAVA_HOME` |
| `jenkins_build_java_package` | `java-26-amazon-corretto-devel` | JDK for Maven builds |
| `jenkins_maven_version` | `3.9.9` | Apache Maven version |
| `jenkins_sonar_scanner_version` | `7.0.2.4839` | SonarScanner CLI version |
| `jenkins_kubectl_version` | `1.36.0` | kubectl client version (align with `deploy-eks` `cluster_version`) |
| `jenkins_kubectl_bin` | `/usr/local/bin/kubectl` | Install path for kubectl |
| `jenkins_install_docker` | `true` | Install Docker Engine and add `jenkins` to the `docker` group |
| `jenkins_docker_package` | `docker` | AL2023 Docker package name |
| `jenkins_update_packages` | `false` | Run `dnf` upgrade of all packages first |
| `jenkins_repo_baseurl` | `https://pkg.jenkins.io/rpm-stable` | Jenkins LTS yum base URL |
| `jenkins_gpg_key_url` | `https://pkg.jenkins.io/rpm-stable/jenkins.io-2026.key` | Repo GPG key |

## Layout

```
install-jenkins/
  ansible.cfg
  inventory.ini.example
  site.yml
  group_vars/all.yml
  roles/jenkins/
    defaults/main.yml
    handlers/main.yml
    tasks/main.yml
    templates/
      jenkins-java21.conf.j2
      maven.sh.j2
      sonar-scanner.sh.j2
    files/
      plugins.txt
```

## Out of scope

- EC2 / VPC / security groups / S3 / EKS IAM wiring (see `deploy-vm`, `deploy-eks`)
- Docker, reverse proxy, TLS, Jenkins Configuration as Code
- Ubuntu/Debian targets (Amazon Linux 2023 only)
