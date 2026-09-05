# sonarqube-java-demo

Build: `mvn package`

Scan: `sonar-scanner`

## GitLab CI

Pipeline (`.gitlab-ci.yml`): **build → test → SonarQube scan → publish**.

Set these CI/CD variables in the GitLab project (**Settings → CI/CD → Variables**):

| Variable | Required | Example |
|---|---|---|
| `SONAR_HOST_URL` | Yes (for scan) | `http://<sonarqube-ip>:9000` |
| `SONAR_TOKEN` | Yes (for scan) | SonarQube user or project token (masked) |
| `SONAR_PROJECT_KEY` | No | Defaults to `sonarqube-java-demo` |

The GitLab runner must be able to reach SonarQube on port 9000.

**Publish** (default branch and tags only):

- Job artifacts: fat JAR under `artifacts/` (kept 30 days)
- GitLab Package Registry: Maven deploy of `com.demo:sonarqube-java-demo`
