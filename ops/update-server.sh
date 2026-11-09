#!/usr/bin/env bash
# Safe way to update the running server after a push to GitHub. Run on the server:
#   sudo bash /opt/libralink/ops/update-server.sh
#
# Why this exists: on 9 Nov a plain "git pull" replaced ops/backup.sh WITHOUT its executable bit
# (the repo is edited on Windows), so the 22:05 backup could not even start ("Permission denied")
# and, because the script never ran, it could not send its own failure e-mail.
set -euo pipefail
cd /opt/libralink

echo "== Pulling the latest code"
git pull

echo "== Making the scripts runnable again"
chmod +x ops/*.sh ops/fault/*.sh

echo "== Installing the systemd services and timers from the repository"
cp ops/systemd/*.service ops/systemd/*.timer /etc/systemd/system/
systemctl daemon-reload

echo "== Timers"
systemctl list-timers 'libralink-*' --no-pager

echo
echo "Done. If files under app/ changed (settings, nginx, branding), also run:"
echo "  sudo systemctl restart libralink"
