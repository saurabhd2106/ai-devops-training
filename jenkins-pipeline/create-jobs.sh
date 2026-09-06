#!/usr/bin/env bash
# Create or update sample Java/Node Pipeline jobs and List Views on Jenkins.
# Requires: curl, and either python3 or sed for template substitution.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${ENV_FILE:-${SCRIPT_DIR}/jobs.env}"
JOB_TEMPLATE="${SCRIPT_DIR}/templates/pipeline-job.xml"
VIEW_TEMPLATE="${SCRIPT_DIR}/templates/list-view.xml"

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "Missing ${ENV_FILE}" >&2
  echo "Copy jobs.env.example to jobs.env and set JENKINS_URL, JENKINS_USER, JENKINS_TOKEN." >&2
  exit 1
fi

# shellcheck disable=SC1090
source "${ENV_FILE}"

: "${JENKINS_URL:?Set JENKINS_URL in jobs.env}"
: "${JENKINS_USER:?Set JENKINS_USER in jobs.env}"
: "${JENKINS_TOKEN:?Set JENKINS_TOKEN in jobs.env}"
REPO_URL="${REPO_URL:-https://github.com/saurabhd2106/ai-devops-training.git}"
BRANCH="${BRANCH:-*/main}"
GIT_CREDENTIALS_ID="${GIT_CREDENTIALS_ID:-}"

JENKINS_URL="${JENKINS_URL%/}"
AUTH=(-u "${JENKINS_USER}:${JENKINS_TOKEN}")

# Job name -> Script Path (relative to repo root)
JOBS=(
  "sample-java-app|sample-java-app/Jenkinsfile|Java S3 CI"
  "sample-java-app-deploy|sample-java-app/Jenkinsfile.deploy-app|Java S3 + Application VM deploy"
  "sample-java-app-ecr|sample-java-app/Jenkinsfile.sonarqube-java-demo|Java Docker + ECR"
  "sample-java-app-ecs|sample-java-app/Jenkinsfile.ecs|Java ECR + ECS"
  "sample-java-app-eks|sample-java-app/Jenkinsfile.eks|Java ECR + EKS"
  "sample-node-app|sample-node-app/Jenkinsfile|Node S3 CI"
  "sample-node-app-deploy|sample-node-app/Jenkinsfile.deploy-app|Node S3 + Application VM deploy"
  "sample-node-app-ecr|sample-node-app/Jenkinsfile.sonarqube-node-demo|Node Docker + ECR"
  "sample-node-app-ecs|sample-node-app/Jenkinsfile.ecs|Node ECR + ECS"
  "sample-node-app-eks|sample-node-app/Jenkinsfile.eks|Node ECR + EKS"
)

VIEWS=(
  "Java|sample-java-app.*"
  "Node|sample-node-app.*"
)

fetch_crumb() {
  local crumb_json field value
  crumb_json="$(curl -fsS "${AUTH[@]}" "${JENKINS_URL}/crumbIssuer/api/json")" || {
    echo "Failed to fetch CSRF crumb from ${JENKINS_URL}/crumbIssuer/api/json" >&2
    echo "Check JENKINS_URL, credentials, and that Jenkins is reachable." >&2
    exit 1
  }
  if command -v python3 >/dev/null 2>&1; then
    field="$(python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["crumbRequestField"])' <<<"${crumb_json}")"
    value="$(python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["crumb"])' <<<"${crumb_json}")"
  elif command -v jq >/dev/null 2>&1; then
    field="$(jq -r '.crumbRequestField' <<<"${crumb_json}")"
    value="$(jq -r '.crumb' <<<"${crumb_json}")"
  else
    echo "Need python3 or jq to parse the CSRF crumb JSON." >&2
    exit 1
  fi
  CRUMB_HEADER=("${field}: ${value}")
}

# Escape sed replacement specials for | delimiter
sed_escape() {
  printf '%s' "$1" | sed -e 's/[\\|&]/\\&/g'
}

render_job_xml() {
  local script_path="$1" description="$2"
  local cred_xml=""
  if [[ -n "${GIT_CREDENTIALS_ID}" ]]; then
    cred_xml="<credentialsId>$(sed_escape "${GIT_CREDENTIALS_ID}")</credentialsId>"
  fi
  sed \
    -e "s|{{JOB_DESCRIPTION}}|$(sed_escape "${description}")|g" \
    -e "s|{{REPO_URL}}|$(sed_escape "${REPO_URL}")|g" \
    -e "s|{{BRANCH}}|$(sed_escape "${BRANCH}")|g" \
    -e "s|{{SCRIPT_PATH}}|$(sed_escape "${script_path}")|g" \
    -e "s|{{GIT_CREDENTIALS_XML}}|${cred_xml}|g" \
    "${JOB_TEMPLATE}"
}

render_view_xml() {
  local view_name="$1" include_regex="$2"
  sed \
    -e "s|{{VIEW_NAME}}|$(sed_escape "${view_name}")|g" \
    -e "s|{{INCLUDE_REGEX}}|$(sed_escape "${include_regex}")|g" \
    "${VIEW_TEMPLATE}"
}

job_exists() {
  local name="$1"
  local code
  code="$(curl -sS -o /dev/null -w '%{http_code}' "${AUTH[@]}" \
    "${JENKINS_URL}/job/$(python3 -c "import urllib.parse; print(urllib.parse.quote('${name}'))")/api/json" || true)"
  [[ "${code}" == "200" ]]
}

view_exists() {
  local name="$1"
  local code
  code="$(curl -sS -o /dev/null -w '%{http_code}' "${AUTH[@]}" \
    "${JENKINS_URL}/view/$(python3 -c "import urllib.parse; print(urllib.parse.quote('${name}'))")/api/json" || true)"
  [[ "${code}" == "200" ]]
}

url_encode() {
  python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=''))" "$1"
}

upsert_job() {
  local name="$1" script_path="$2" description="$3"
  local xml encoded
  xml="$(render_job_xml "${script_path}" "${description}")"
  encoded="$(url_encode "${name}")"

  if job_exists "${name}"; then
    echo "Updating job: ${name}"
    curl -fsS "${AUTH[@]}" \
      -H "${CRUMB_HEADER[0]}" \
      -H "Content-Type: application/xml" \
      -X POST \
      --data-binary "${xml}" \
      "${JENKINS_URL}/job/${encoded}/config.xml" >/dev/null
  else
    echo "Creating job: ${name}"
    curl -fsS "${AUTH[@]}" \
      -H "${CRUMB_HEADER[0]}" \
      -H "Content-Type: application/xml" \
      -X POST \
      --data-binary "${xml}" \
      "${JENKINS_URL}/createItem?name=${encoded}" >/dev/null
  fi
}

upsert_view() {
  local name="$1" include_regex="$2"
  local xml encoded
  xml="$(render_view_xml "${name}" "${include_regex}")"
  encoded="$(url_encode "${name}")"

  if view_exists "${name}"; then
    echo "Updating view: ${name}"
    curl -fsS "${AUTH[@]}" \
      -H "${CRUMB_HEADER[0]}" \
      -H "Content-Type: application/xml" \
      -X POST \
      --data-binary "${xml}" \
      "${JENKINS_URL}/view/${encoded}/config.xml" >/dev/null
  else
    echo "Creating view: ${name}"
    # createView expects form-encoded name/mode, then config via config.xml
    curl -fsS "${AUTH[@]}" \
      -H "${CRUMB_HEADER[0]}" \
      -X POST \
      --data-urlencode "name=${name}" \
      --data-urlencode "mode=hudson.model.ListView" \
      --data-urlencode "json={\"name\":\"${name}\",\"mode\":\"hudson.model.ListView\"}" \
      "${JENKINS_URL}/createView" >/dev/null
    curl -fsS "${AUTH[@]}" \
      -H "${CRUMB_HEADER[0]}" \
      -H "Content-Type: application/xml" \
      -X POST \
      --data-binary "${xml}" \
      "${JENKINS_URL}/view/${encoded}/config.xml" >/dev/null
  fi
}

main() {
  if ! command -v python3 >/dev/null 2>&1; then
    echo "python3 is required for URL encoding." >&2
    exit 1
  fi
  if [[ ! -f "${JOB_TEMPLATE}" || ! -f "${VIEW_TEMPLATE}" ]]; then
    echo "Missing templates under ${SCRIPT_DIR}/templates/" >&2
    exit 1
  fi

  echo "Jenkins: ${JENKINS_URL}"
  fetch_crumb

  local entry name script_path description
  for entry in "${JOBS[@]}"; do
    IFS='|' read -r name script_path description <<<"${entry}"
    upsert_job "${name}" "${script_path}" "${description}"
  done

  local view_name include_regex
  for entry in "${VIEWS[@]}"; do
    IFS='|' read -r view_name include_regex <<<"${entry}"
    upsert_view "${view_name}" "${include_regex}"
  done

  echo "Done. Open ${JENKINS_URL}/ and check the Java and Node view tabs."
}

main "$@"
