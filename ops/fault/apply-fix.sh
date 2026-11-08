#!/usr/bin/env bash
# WS-F FIX + PREVENTION for the disk-full incident.
#   sudo /opt/libralink/ops/fault/apply-fix.sh
#
# Fix:        remove the runaway log file, restart the app so the database recovers.
# Prevention: 1) log rotation with a 50 MB cap for /var/log/libralink (every 15 minutes)
#             2) cap the systemd journal at 200 MB
#             (the disk alarm at 85% was already there - it is how we noticed)
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"

"$here/timeline.sh" "fix started"
echo "Biggest files under /var/log (the culprit should be at the top):"
du -ah /var/log 2>/dev/null | sort -rh | head -5

# --- fix ---
rm -f /var/log/libralink/debug-trace.log
# A file deleted while a process still holds it open keeps using space; show any:
lsof +L1 2>/dev/null | head -5 || true
systemctl restart libralink.service
df -h /

# --- prevention ---
install -m 0644 "$here/logrotate-libralink" /etc/logrotate.d/libralink
cat > /etc/systemd/system/logrotate-libralink.service <<'EOF'
[Unit]
Description=Rotate LibraLink logs (size-capped)
[Service]
Type=oneshot
ExecStart=/usr/sbin/logrotate --state /var/lib/libralink/logrotate.status /etc/logrotate.d/libralink
EOF
cat > /etc/systemd/system/logrotate-libralink.timer <<'EOF'
[Unit]
Description=Rotate LibraLink logs every 15 minutes
[Timer]
OnCalendar=*:0/15
Persistent=true
[Install]
WantedBy=timers.target
EOF
mkdir -p /etc/systemd/journald.conf.d
printf '[Journal]\nSystemMaxUse=200M\n' > /etc/systemd/journald.conf.d/libralink.conf
systemctl daemon-reload
systemctl restart systemd-journald
systemctl enable --now logrotate-libralink.timer

"$here/timeline.sh" "fixed: disk freed, app restarted, log rotation + journal cap installed"
echo
echo "Next: run $here/verify-fix.sh to prove the rotation works."
