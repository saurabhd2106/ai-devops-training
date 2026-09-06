#!/usr/bin/env bash
# Advisory Amazon Bedrock review for Jenkins pipelines.
# Modes: tests | sonar | change | deploy
# Never exits non-zero for Bedrock/API failures (advisory only).
set -u

MODE="${1:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"; then
  :
else
  REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
fi

MAX_CHARS="${AI_MAX_CHARS:-14000}"
MODEL_ID="${BEDROCK_MODEL_ID:-us.amazon.nova-lite-v1:0}"
REGION="${AWS_DEFAULT_REGION:-${AWS_REGION:-us-east-1}}"
OUT_DIR="${AI_OUT_DIR:-${WORKSPACE:-.}/ai-review}"
APP_DIR="${APP_DIR:-.}"
DEPLOY_DIAG="${AI_DEPLOY_DIAG:-${WORKSPACE:-.}/ai-review/deploy-diagnostics.json}"

usage() {
  echo "Usage: $0 <tests|sonar|change|deploy>" >&2
}

skip() {
  local reason="$1"
  mkdir -p "${OUT_DIR}"
  {
    echo "# AI review skipped (${MODE:-unknown})"
    echo
    echo "${reason}"
  } > "${OUT_DIR}/${MODE:-unknown}.md"
  echo "AI review skipped (${MODE}): ${reason}"
  exit 0
}

if [ -z "${MODE}" ]; then
  usage
  skip "No mode argument provided."
fi

case "${MODE}" in
  tests|sonar|change|deploy) ;;
  *)
    usage
    MODE="unknown"
    skip "Unknown mode '${1}'. Expected tests|sonar|change|deploy."
    ;;
esac

command -v aws >/dev/null 2>&1 || skip "aws CLI not found on PATH."
command -v python3 >/dev/null 2>&1 || skip "python3 not found on PATH."
aws bedrock-runtime help >/dev/null 2>&1 || skip "aws CLI lacks bedrock-runtime (need AWS CLI v2 with Bedrock support on the Jenkins agent)."

PROMPT_FILE="${SCRIPT_DIR}/prompts/${MODE}.txt"
[ -f "${PROMPT_FILE}" ] || skip "Prompt file missing: ${PROMPT_FILE}"

mkdir -p "${OUT_DIR}"
FACTS_FILE="$(mktemp)"
USER_MSG_FILE="$(mktemp)"
REQUEST_FILE="$(mktemp)"
RESPONSE_FILE="$(mktemp)"
cleanup() {
  rm -f "${FACTS_FILE}" "${USER_MSG_FILE}" "${REQUEST_FILE}" "${RESPONSE_FILE}"
}
trap cleanup EXIT

# Resolve application directory relative to workspace / cwd.
resolve_app_path() {
  local rel="$1"
  if [ -n "${APP_DIR}" ] && [ "${APP_DIR}" != "." ] && [ -e "${APP_DIR}/${rel}" ]; then
    echo "${APP_DIR}/${rel}"
  elif [ -e "${rel}" ]; then
    echo "${rel}"
  else
    echo ""
  fi
}

collect_tests() {
  python3 - "${APP_DIR}" <<'PY'
import glob
import os
import sys

app = sys.argv[1] if len(sys.argv) > 1 else "."
patterns = [
    os.path.join(app, "target/surefire-reports/*.xml"),
    os.path.join(app, "reports/junit/*.xml"),
    "target/surefire-reports/*.xml",
    "reports/junit/*.xml",
]
files = []
seen = set()
for pat in patterns:
    for path in sorted(glob.glob(pat)):
        ap = os.path.abspath(path)
        if ap not in seen:
            seen.add(ap)
            files.append(path)

print("## JUnit / Surefire / Jest XML")
if not files:
    print("(no report XML found under target/surefire-reports or reports/junit)")
else:
    for path in files[:20]:
        print(f"\n### FILE: {path}\n")
        try:
            with open(path, "r", encoding="utf-8", errors="replace") as fh:
                print(fh.read())
        except OSError as exc:
            print(f"(unreadable: {exc})")

cov_dirs = [
    os.path.join(app, "coverage"),
    os.path.join(app, "target/site/jacoco"),
    "coverage",
    "target/site/jacoco",
]
print("\n## Coverage artefacts present")
found_cov = False
for d in cov_dirs:
    if os.path.isdir(d):
        found_cov = True
        names = sorted(os.listdir(d))[:30]
        print(f"- {d}: {', '.join(names) if names else '(empty)'}")
if not found_cov:
    print("- (none)")
PY
}

collect_sonar() {
  local host="${SONAR_HOST_URL:-}"
  local token="${SONAR_TOKEN:-}"
  local key="${SONAR_PROJECT_KEY:-}"

  if [ -z "${key}" ]; then
    local props
    props="$(resolve_app_path sonar-project.properties)"
    if [ -n "${props}" ] && [ -f "${props}" ]; then
      key="$(grep -E '^sonar\.projectKey=' "${props}" | head -n1 | cut -d= -f2- | tr -d '\r')"
    fi
  fi

  if [ -z "${host}" ]; then
    echo "## SonarQube"
    echo "(SONAR_HOST_URL not set)"
    return
  fi
  if [ -z "${token}" ]; then
    echo "## SonarQube"
    echo "(SONAR_TOKEN not set)"
    return
  fi
  if [ -z "${key}" ]; then
    echo "## SonarQube"
    echo "(SONAR_PROJECT_KEY not set and sonar-project.properties not found)"
    return
  fi

  host="${host%/}"
  echo "## SonarQube unresolved issues"
  echo "projectKey=${key}"
  echo "host=${host}"
  echo
  # Prefer curl; fall back to python urllib.
  if command -v curl >/dev/null 2>&1; then
    curl -fsS -u "${token}:" \
      "${host}/api/issues/search?componentKeys=${key}&resolved=false&ps=50&facets=severities,types" \
      || echo '{"error":"sonar api request failed"}'
  else
    python3 - "${host}" "${token}" "${key}" <<'PY'
import json, sys, urllib.request, base64
host, token, key = sys.argv[1:4]
url = f"{host}/api/issues/search?componentKeys={key}&resolved=false&ps=50&facets=severities,types"
req = urllib.request.Request(url)
auth = base64.b64encode(f"{token}:".encode()).decode()
req.add_header("Authorization", f"Basic {auth}")
try:
    with urllib.request.urlopen(req, timeout=60) as resp:
        print(resp.read().decode("utf-8", errors="replace"))
except Exception as exc:
    print(json.dumps({"error": str(exc)}))
PY
  fi
}

collect_change() {
  echo "## Recent commits (git log -10 --oneline)"
  if git -C "${REPO_ROOT}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git -C "${REPO_ROOT}" log -10 --oneline 2>/dev/null || echo "(git log failed)"
  elif git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git log -10 --oneline 2>/dev/null || echo "(git log failed)"
  else
    echo "(not a git work tree)"
  fi
  echo
  echo "## Diff"
  local base=""
  if git rev-parse --verify origin/main >/dev/null 2>&1; then
    base="origin/main"
  elif git rev-parse --verify main >/dev/null 2>&1; then
    base="main"
  fi
  if [ -n "${base}" ]; then
    echo "(against ${base}...HEAD)"
    git diff --stat "${base}...HEAD" 2>/dev/null || true
    echo
    git diff "${base}...HEAD" 2>/dev/null || echo "(git diff failed)"
  else
    echo "(no main branch; showing last commit)"
    git show --stat HEAD 2>/dev/null || true
    echo
    git show --format=fuller HEAD 2>/dev/null || echo "(git show failed)"
  fi
}

collect_deploy() {
  echo "## Deploy diagnostics"
  if [ -f "${DEPLOY_DIAG}" ]; then
    echo "source=${DEPLOY_DIAG}"
    cat "${DEPLOY_DIAG}"
  else
    echo "(no diagnostics file at ${DEPLOY_DIAG})"
    echo "Set AI_DEPLOY_DIAG or write JSON/text to ai-review/deploy-diagnostics.json from the deploy stage."
  fi
}

case "${MODE}" in
  tests)  collect_tests  > "${FACTS_FILE}" ;;
  sonar)  collect_sonar  > "${FACTS_FILE}" ;;
  change) collect_change > "${FACTS_FILE}" ;;
  deploy) collect_deploy > "${FACTS_FILE}" ;;
esac

case "${MODE}" in
  tests)  PLACEHOLDER='{{TEST_RESULTS}}' ;;
  sonar)  PLACEHOLDER='{{SONAR_ISSUES_JSON}}' ;;
  change) PLACEHOLDER='{{COMMITS_AND_DIFF}}' ;;
  deploy) PLACEHOLDER='{{DEPLOY_DIAGNOSTICS}}' ;;
esac

SCHEMA_FILE="${SCRIPT_DIR}/prompts/change-schema.json"
MAX_TOKENS=1200
if [ "${MODE}" = "change" ]; then
  MAX_TOKENS=1600
fi

set +e
python3 - "${PROMPT_FILE}" "${FACTS_FILE}" "${USER_MSG_FILE}" "${MAX_CHARS}" "${PLACEHOLDER}" "${MODE}" "${SCHEMA_FILE}" <<'PY'
import re
import sys

prompt_path, facts_path, out_path, max_chars_s, placeholder, mode, schema_path = sys.argv[1:8]
max_chars = int(max_chars_s)

with open(prompt_path, "r", encoding="utf-8") as fh:
    prompt = fh.read()
with open(facts_path, "r", encoding="utf-8", errors="replace") as fh:
    facts = fh.read()

if placeholder not in prompt:
    print(f"PROMPT_PLACEHOLDER_MISSING:{placeholder}", file=sys.stderr)
    sys.exit(2)

redact_patterns = [
    (re.compile(r"(?i)(authorization:\s*basic\s+)\S+"), r"\1[REDACTED]"),
    (re.compile(r"(?i)(bearer\s+)[A-Za-z0-9._\-]+"), r"\1[REDACTED]"),
    (re.compile(r"AKIA[0-9A-Z]{16}"), "AKIA[REDACTED]"),
    (re.compile(r"(?i)(aws_secret_access_key\s*[=:]\s*)\S+"), r"\1[REDACTED]"),
    (re.compile(r"(?i)(sonar\.?token\s*[=:]\s*)\S+"), r"\1[REDACTED]"),
    (re.compile(r"(?i)(SONAR_TOKEN\s*[=:]\s*)\S+"), r"\1[REDACTED]"),
    (re.compile(r"(?i)(password\s*[=:]\s*)\S+"), r"\1[REDACTED]"),
    (re.compile(r"(?i)(secret\s*[=:]\s*)\S+"), r"\1[REDACTED]"),
]
for cre, repl in redact_patterns:
    facts = cre.sub(repl, facts)

if len(facts) > max_chars:
    facts = facts[:max_chars] + "\n\n...[truncated for prompt size]...\n"

user = prompt.replace(placeholder, facts, 1)

if mode == "change":
    try:
        with open(schema_path, "r", encoding="utf-8") as fh:
            schema = fh.read().strip()
    except OSError:
        print(f"SCHEMA_MISSING:{schema_path}", file=sys.stderr)
        sys.exit(3)
    user = (
        user.rstrip()
        + "\n\n## Output JSON Schema\n\n"
        + "Return a single JSON object that conforms to this schema:\n\n"
        + schema
        + "\n"
    )

with open(out_path, "w", encoding="utf-8") as fh:
    fh.write(user)
PY
ASM_RC=$?
set -e

if [ "${ASM_RC}" -eq 2 ]; then
  skip "Prompt file is missing required placeholder ${PLACEHOLDER}."
fi
if [ "${ASM_RC}" -eq 3 ]; then
  skip "change-schema.json missing at ${SCHEMA_FILE}."
fi
if [ "${ASM_RC}" -ne 0 ]; then
  skip "Failed to assemble prompt (exit ${ASM_RC})."
fi

python3 - "${USER_MSG_FILE}" "${REQUEST_FILE}" "${MODEL_ID}" "${MAX_TOKENS}" <<'PY'
import json
import os
import sys

user_path, req_path, model_id, max_tokens_s = sys.argv[1:5]
with open(user_path, "r", encoding="utf-8") as fh:
    text = fh.read()

body = {
    "modelId": model_id,
    "messages": [
        {
            "role": "user",
            "content": [{"text": text}],
        }
    ],
    "inferenceConfig": {
        "maxTokens": int(max_tokens_s),
        "temperature": 0.2,
    },
}

guardrail_id = os.environ.get("BEDROCK_GUARDRAIL_ID", "").strip()
guardrail_version = os.environ.get("BEDROCK_GUARDRAIL_VERSION", "DRAFT").strip() or "DRAFT"
if guardrail_id:
    body["guardrailConfig"] = {
        "guardrailIdentifier": guardrail_id,
        "guardrailVersion": guardrail_version,
    }

with open(req_path, "w", encoding="utf-8") as fh:
    json.dump(body, fh)
PY

echo "Calling Bedrock Converse model=${MODEL_ID} region=${REGION} mode=${MODE}"
set +e
aws bedrock-runtime converse \
  --region "${REGION}" \
  --cli-input-json "file://${REQUEST_FILE}" \
  --output json > "${RESPONSE_FILE}" 2>"${OUT_DIR}/${MODE}.err"
AWS_RC=$?
set -e

OUT_MD="${OUT_DIR}/${MODE}.md"

if [ "${AWS_RC}" -ne 0 ]; then
  {
    echo "# AI ${MODE} review — Bedrock call failed"
    echo
    echo "The AI layer is advisory and did not fail the pipeline."
    echo
    echo '```'
    cat "${OUT_DIR}/${MODE}.err" 2>/dev/null || echo "(no stderr)"
    echo '```'
    echo
    echo "Check: deploy-bedrock applied, bedrock_invoke_policy_arn attached to deploy-vm instance role, model access in ${REGION}."
  } > "${OUT_MD}"
  cat "${OUT_MD}"
  exit 0
fi

python3 - "${RESPONSE_FILE}" "${OUT_MD}" "${MODE}" "${MODEL_ID}" "${OUT_DIR}" <<'PY'
import json
import re
import sys
from pathlib import Path

resp_path, out_path, mode, model_id, out_dir = sys.argv[1:6]
with open(resp_path, "r", encoding="utf-8") as fh:
    data = json.load(fh)

chunks = []
for block in data.get("output", {}).get("message", {}).get("content", []) or []:
    if isinstance(block, dict) and "text" in block:
        chunks.append(block["text"])
text = "\n".join(chunks).strip() or "(empty model response)"

stop = data.get("stopReason", "")
usage = data.get("usage", {})
header = (
    f"# AI {mode} review\n\n"
    f"_Model: `{model_id}` · stopReason: `{stop}` · "
    f"tokens in/out: {usage.get('inputTokens', '?')}/{usage.get('outputTokens', '?')}_\n\n"
)

def extract_json(raw: str):
    raw = raw.strip()
    fence = re.search(r"```(?:json)?\s*([\s\S]*?)\s*```", raw)
    if fence:
        raw = fence.group(1).strip()
    try:
        return json.loads(raw)
    except json.JSONDecodeError:
        start = raw.find("{")
        end = raw.rfind("}")
        if start >= 0 and end > start:
            try:
                return json.loads(raw[start : end + 1])
            except json.JSONDecodeError:
                return None
        return None

out = Path(out_path)
if mode == "change":
    parsed = extract_json(text)
    json_path = Path(out_dir) / "change.json"
    if parsed is not None:
        json_path.write_text(json.dumps(parsed, indent=2) + "\n", encoding="utf-8")
        body = "```json\n" + json.dumps(parsed, indent=2) + "\n```\n"
        out.write_text(header + body, encoding="utf-8")
    else:
        out.write_text(
            header
            + "Model response was not valid JSON. Raw output:\n\n```\n"
            + text
            + "\n```\n",
            encoding="utf-8",
        )
else:
    out.write_text(header + text + "\n", encoding="utf-8")
PY

echo "----- AI ${MODE} review -----"
cat "${OUT_MD}"
echo "----- end AI ${MODE} review -----"
exit 0
