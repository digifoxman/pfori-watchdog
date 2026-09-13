#!/usr/bin/env bash
set -euo pipefail

REMOTE=projectxv
REMOTE_DIR=/var/www/project-xv/watchdog
LOCAL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "==> Ensuring $REMOTE_DIR exists"
ssh "$REMOTE" "mkdir -p $REMOTE_DIR"

echo "==> Syncing files to $REMOTE:$REMOTE_DIR"
rsync -avz --delete \
  --exclude 'node_modules' \
  --exclude '.git' \
  --exclude 'watchdog.log' \
  --exclude 'status.json' \
  --exclude '.env' \
  "$LOCAL_DIR/scripts" "$LOCAL_DIR/run-checks.js" "$LOCAL_DIR/app" \
  "$REMOTE:$REMOTE_DIR/"

echo "==> Installing dashboard dependencies"
ssh "$REMOTE" "cd $REMOTE_DIR/app && npm install --omit=dev"

echo "==> Installing systemd units"
scp "$LOCAL_DIR"/deploy/watchdog-checks.service "$LOCAL_DIR"/deploy/watchdog-checks.timer "$LOCAL_DIR"/deploy/watchdog-app.service "$REMOTE:/tmp/"
ssh "$REMOTE" "
  sudo mv /tmp/watchdog-checks.service /tmp/watchdog-checks.timer /tmp/watchdog-app.service /etc/systemd/system/ &&
  sudo chmod +x $REMOTE_DIR/run-checks.js $REMOTE_DIR/scripts/check-*.sh &&
  sudo systemctl daemon-reload &&
  sudo systemctl enable --now watchdog-checks.timer &&
  sudo systemctl enable --now watchdog-app.service &&
  sudo systemctl restart watchdog-app.service
"

echo "==> Done. Check status with:"
echo "    ssh $REMOTE systemctl status watchdog-checks.timer watchdog-app.service"
echo "    ssh $REMOTE journalctl -u watchdog-checks.service -n 20"
