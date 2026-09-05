# sonarqube-java-demo

Maven Spring Boot demo for SonarQube training (intentional code-quality issues and one failing test).

## Local build and scan

```bash
mvn package
sonar-scanner
```

## Jenkins CI pipeline

Declarative pipeline: [`Jenkinsfile`](Jenkinsfile).

| Stage | What it does |
|-------|----------------|
| Checkout | SCM checkout; resolves `sample-java-app/` vs app-only root |
| Build | `mvn -B -DskipTests compile` |
| Test | `mvn -B test` + JUnit report publish (Surefire ignores failures for training) |
| SonarQube Scan | `mvn package` then `sonar-scanner` (no quality-gate wait) |
| Publish artefacts | Jenkins `archiveArtifacts` + upload JAR/reports to S3 |

### Prerequisites (lab)

1. Apply Terraform in [`deploy-vm`](../deploy-vm) (creates VMs, CI S3 bucket, Jenkins→SonarQube:9000 SG rule).
2. Install SonarQube with [`install-sonarqube`](../install-sonarqube).
3. Install Jenkins + build tools with [`install-jenkins`](../install-jenkins) (JDK 26, Maven, sonar-scanner, plugins).
4. In SonarQube UI: create a user token for project `sonarqube-java-demo`.
5. In Jenkins UI:
   - **Credentials** → add Secret text, ID = `sonarqube-token` (paste the SonarQube token).
   - **New Item** → Pipeline → Pipeline script from SCM.
   - Script Path: `sample-java-app/Jenkinsfile` (monorepo) or `Jenkinsfile` (app-only checkout).
6. On first run, set parameters:
   - `SONAR_HOST_URL` = `http://<sonarqube-private-ip>:9000`  
     (`terraform -chdir=../deploy-vm output -json private_ips`)
   - `S3_BUCKET` = value of `terraform -chdir=../deploy-vm output -raw ci_artifacts_bucket`

Artefacts land at:

- Jenkins build archive: `target/sonarqube-java-demo-*.jar`, surefire XML
- S3: `s3://<bucket>/sample-java-app/<BUILD_NUMBER>/`
