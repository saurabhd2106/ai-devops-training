# ci/ai — advisory Amazon Bedrock reviews for Jenkins and GitLab CI

Shared script used by Java and Node **Jenkinsfiles** and **GitLab CI** jobs to call
**Amazon Bedrock Converse** after tests, SonarQube, change review, and (on failure)
deploy. Reviews are **advisory**: they never fail the build and never gate deploy.

## Modes

| Mode | Prompt | Input placeholder | Output |
|------|--------|-------------------|--------|
| `tests` | `prompts/tests.txt` | `{{TEST_RESULTS}}` | `ai-review/tests.md` (Markdown) |
| `sonar` | `prompts/sonar.txt` | `{{SONAR_ISSUES_JSON}}` | `ai-review/sonar.md` (Markdown) |
| `change` | `prompts/change.txt` + `change-schema.json` | `{{COMMITS_AND_DIFF}}` | `ai-review/change.json` + `change.md` |
| `deploy` | `prompts/deploy.txt` | `{{DEPLOY_DIAGNOSTICS}}` | `ai-review/deploy.md` (Markdown) |

`ai-review.sh` redacts secrets, truncates the payload, **substitutes the placeholder
inside the prompt** (it does not append a separate “Input facts” section), and for
`change` appends the JSON schema so the model has the supplied contract.

`change` risk / `strategy` values are recorded only. Jenkins and GitLab do **not**
branch or block deploy on them in this lab.

## Prerequisites

1. Apply [`deploy-bedrock`](../../deploy-bedrock) (Nova Lite is enough).
2. Attach `invoke_policy_arn` to the CI caller identity:
   - Jenkins: `deploy-vm` `bedrock_invoke_policy_arn` on the EC2 instance role
   - GitLab: same attachment on a self-hosted runner’s instance profile, **or** an IAM user whose keys are stored as GitLab CI/CD variables
3. Optional env (Jenkins global env or GitLab CI/CD variables): `BEDROCK_MODEL_ID`, `BEDROCK_GUARDRAIL_ID`, `BEDROCK_GUARDRAIL_VERSION`

Also set for `sonar` mode: `SONAR_HOST_URL`, `SONAR_TOKEN`, and optionally `SONAR_PROJECT_KEY`.

## Environment variables used by the script

| Variable | Default | Purpose |
|----------|---------|---------|
| `BEDROCK_MODEL_ID` | `us.amazon.nova-lite-v1:0` | Bedrock model / inference profile |
| `AWS_DEFAULT_REGION` / `AWS_REGION` | `us-east-1` | Bedrock region |
| `AI_MAX_CHARS` | `14000` | Input truncation |
| `AI_OUT_DIR` | `${WORKSPACE}/ai-review` | Output directory (GitLab sets `WORKSPACE=$CI_PROJECT_DIR`) |
| `APP_DIR` | `.` | App subdir for test/coverage paths |
| `AI_DEPLOY_DIAG` | `ai-review/deploy-diagnostics.json` | Deploy RCA input |
| `SONAR_HOST_URL` / `SONAR_TOKEN` / `SONAR_PROJECT_KEY` | — | Sonar API in `sonar` mode |
| `BEDROCK_GUARDRAIL_ID` / `BEDROCK_GUARDRAIL_VERSION` | — / `DRAFT` | Optional Guardrail |

## Layout

```
ci/ai/
  ai-review.sh
  prompts/{tests,sonar,change,deploy}.txt
  prompts/change-schema.json
  README.md
```

Copies under `sample-java-app/ci/ai/` and `sample-node-app/ci/ai/` support app-only
SCM checkouts. Monorepo jobs prefer `ci/ai/ai-review.sh`.

## Local smoke test

```bash
export APP_DIR=sample-java-app
export AWS_DEFAULT_REGION=us-east-1
./ci/ai/ai-review.sh change
cat ai-review/change.md
# when Bedrock succeeds and returns valid JSON:
# cat ai-review/change.json
```

Missing IAM, an old AWS CLI without `bedrock-runtime`, or model access writes a skip
markdown file and exits **0**.
