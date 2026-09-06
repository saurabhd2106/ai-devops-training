#!/usr/bin/env bash
# Deploy sonarqube-node-demo tarball onto the Application VM (Amazon Linux 2023).
# Invoked via SSM RunShellScript from Jenkinsfile.deploy-app.
#
# Required env (set by the SSM command):
#   S3_BUCKET  — CI artefacts bucket
#   S3_PREFIX  — e.g. sample-node-app/<BUILD_NUMBER>
#   TARBALL_NAME — e.g. sonarqube-node-demo-1.0.0.tgz
# Optional:
#   AWS_DEFAULT_REGION — defaults to us-east-1

set -euo pipefail

: "${S3_BUCKET:?S3_BUCKET is required}"
: "${S3_PREFIX:?S3_PREFIX is required}"
: "${TARBALL_NAME:?TARBALL_NAME is required}"

export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-1}"

APP_DIR="/opt/sample-node-app"
SERVICE_NAME="sample-node-app"
SERVICE_UNIT="/etc/systemd/system/${SERVICE_NAME}.service"
HEALTH_URL="http://127.0.0.1/health"
TARBALL_PATH="/tmp/${TARBALL_NAME}"

echo "==> Ensuring Node.js 20 is installed"
if ! command -v node >/dev/null 2>&1; then
  dnf install -y nodejs20
fi
NODE_BIN="$(command -v node)"
node --version
npm --version

if ! command -v curl >/dev/null 2>&1; then
  dnf install -y curl-minimal || dnf install -y curl
fi

echo "==> Preparing ${APP_DIR}"
rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}"

echo "==> Downloading s3://${S3_BUCKET}/${S3_PREFIX}/${TARBALL_NAME}"
aws s3 cp "s3://${S3_BUCKET}/${S3_PREFIX}/${TARBALL_NAME}" "${TARBALL_PATH}" --only-show-errors
tar -xzf "${TARBALL_PATH}" -C "${APP_DIR}"
rm -f "${TARBALL_PATH}"

if [ ! -f "${SERVICE_UNIT}" ]; then
  echo "==> Writing systemd unit ${SERVICE_UNIT}"
  cat > "${SERVICE_UNIT}" <<EOF
[Unit]
Description=sonarqube-node-demo (sample-node-app)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=${APP_DIR}
Environment=PORT=80
Environment=NODE_ENV=production
ExecStart=${NODE_BIN} ${APP_DIR}/app.js
Restart=on-failure
RestartSec=5
SuccessExitStatus=143

[Install]
WantedBy=multi-user.target
EOF
else
  # Keep ExecStart pointing at the current node binary after upgrades
  sed -i "s|^ExecStart=.*|ExecStart=${NODE_BIN} ${APP_DIR}/app.js|" "${SERVICE_UNIT}"
fi

echo "==> Reloading and restarting ${SERVICE_NAME}"
systemctl daemon-reload
systemctl enable "${SERVICE_NAME}"
systemctl restart "${SERVICE_NAME}"

echo "==> Waiting for health check ${HEALTH_URL}"
for i in $(seq 1 30); do
  if curl -sf "${HEALTH_URL}" >/dev/null; then
    echo "Health check OK (attempt ${i})"
    curl -sS "${HEALTH_URL}" || true
    echo
    systemctl --no-pager --full status "${SERVICE_NAME}" || true
    exit 0
  fi
  sleep 2
done

echo "Health check failed after ~60s"
systemctl --no-pager --full status "${SERVICE_NAME}" || true
journalctl -u "${SERVICE_NAME}" -n 50 --no-pager || true
exit 1
