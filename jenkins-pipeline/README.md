# jenkins-pipeline — create sample jobs and views via Jenkins API

Creates the sample **Java** and **Node** Pipeline jobs on an already-configured Jenkins controller, then groups them into two List Views (`Java`, `Node`).

Does **not** install Jenkins, set credentials, tools, or global env vars. Do that first with [`install-jenkins`](../install-jenkins) and the steps in [`sample-java-app/README.md`](../sample-java-app/README.md) / [`sample-node-app/README.md`](../sample-node-app/README.md).

## Prerequisites

- Jenkins reachable at `:8080` with Pipeline + Git plugins (installed by `install-jenkins`)
- Global env: `SONAR_HOST_URL`, `S3_BUCKET` (and optional `APP_INSTANCE_ID`)
- Credential ID **`sonarqube-token`**
- A Jenkins user API token (user → **Security** → **API Token** → **Generate**)
- Local tools: `curl`, `python3` (and `bash`)

## Quick start

```bash
cd jenkins-pipeline

cp jobs.env.example jobs.env
# Edit jobs.env: JENKINS_URL, JENKINS_USER, JENKINS_TOKEN
# Optional: REPO_URL, BRANCH, GIT_CREDENTIALS_ID (private Git only)

./create-jobs.sh
```

Open `http://<jenkins-public-ip>:8080/` and use the **Java** and **Node** tabs (jobs also remain on **All**).

## What it creates

### Jobs (Pipeline script from SCM)

| Job | Script Path |
|-----|-------------|
| `sample-java-app` | `sample-java-app/Jenkinsfile` |
| `sample-java-app-deploy` | `sample-java-app/Jenkinsfile.deploy-app` |
| `sample-java-app-ecr` | `sample-java-app/Jenkinsfile.sonarqube-java-demo` |
| `sample-java-app-ecs` | `sample-java-app/Jenkinsfile.ecs` |
| `sample-java-app-eks` | `sample-java-app/Jenkinsfile.eks` |
| `sample-node-app` | `sample-node-app/Jenkinsfile` |
| `sample-node-app-deploy` | `sample-node-app/Jenkinsfile.deploy-app` |
| `sample-node-app-ecr` | `sample-node-app/Jenkinsfile.sonarqube-node-demo` |
| `sample-node-app-ecs` | `sample-node-app/Jenkinsfile.ecs` |
| `sample-node-app-eks` | `sample-node-app/Jenkinsfile.eks` |

Defaults: repo `https://github.com/saurabhd2106/ai-devops-training.git`, branch `*/main`. Override in `jobs.env`.

The script is **idempotent**: existing jobs are updated via `POST /job/<name>/config.xml`; missing jobs use `POST /createItem`.

### Views

| View | Regex |
|------|-------|
| `Java` | `sample-java-app.*` |
| `Node` | `sample-node-app.*` |

Same create-or-update pattern via `/createView` and `/view/<name>/config.xml`.

## Layout

```
jenkins-pipeline/
  README.md
  create-jobs.sh
  jobs.env.example
  .gitignore          # ignores jobs.env (secrets)
  templates/
    pipeline-job.xml
    list-view.xml
```

## Manual alternative

You can still create jobs in the UI: **New Item** → **Pipeline** → **Pipeline script from SCM** with the Script Paths above. This folder is the API path for the same result.
