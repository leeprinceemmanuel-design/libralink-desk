#!/usr/bin/env bash
# First-boot setup for the LibraLink Desk server (Amazon Linux 2023).
# Used as EC2 user data by ops/aws/06-ec2.sh, so it runs once, as root, with nobody logged in.
# Its output goes to /var/log/cloud-init-output.log.
#
# What it does: installs Docker + Compose, the CloudWatch agent and Python; adds 2 GB swap;
# downloads this repository to /opt/libralink; installs the systemd services and timers;
# starts the app.
#
# NOTE (on purpose, for the WS-F incident): log rotation for /var/log/libralink is NOT set up
# here. ops/fault/apply-fix.sh adds it as the fix after the disk-full incident.
set -euxo pipefail

REPO_URL="__REPO_URL__"          # replaced by 06-ec2.sh
REPO_BRANCH="__REPO_BRANCH__"

dnf install -y docker git python3 amazon-cloudwatch-agent logrotate
systemctl enable --now docker
usermod -aG docker ec2-user

# Docker Compose v2 plugin (not packaged for Amazon Linux 2023).
mkdir -p /usr/local/lib/docker/cli-plugins
curl -fsSL "https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64" \
  -o /usr/local/lib/docker/cli-plugins/docker-compose
chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
docker compose version

# 2 GB swap, so a short memory spike slows things down instead of killing the app.
if [[ ! -f /swapfile ]]; then
  dd if=/dev/zero of=/swapfile bs=1M count=2048
  chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile
  echo '/swapfile none swap defaults 0 0' >> /etc/fstab
fi

# Get the code.
rm -rf /opt/libralink
git clone --depth 1 --branch "$REPO_BRANCH" "$REPO_URL" /opt/libralink
chmod +x /opt/libralink/ops/*.sh /opt/libralink/ops/fault/*.sh

mkdir -p /var/log/libralink/nginx /var/lib/libralink
touch /var/log/libralink/{requests.log,automation.log}

# CloudWatch agent: memory, disk and swap metrics + our three log files.
cp /opt/libralink/ops/cloudwatch-agent.json /opt/aws/amazon-cloudwatch-agent/etc/libralink.json
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -s \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/libralink.json

# systemd: the app + two timers (request logger every minute, backup every hour).
cp /opt/libralink/ops/systemd/*.service /opt/libralink/ops/systemd/*.timer /etc/systemd/system/
systemctl daemon-reload
systemctl enable libralink.service
systemctl start libralink.service
systemctl enable --now libralink-exporter.timer libralink-backup.timer

echo "LibraLink bootstrap finished at $(date -u +%FT%TZ)"
