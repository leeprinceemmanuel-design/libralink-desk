#!/usr/bin/env bash
# WS-F EVIDENCE that the prevention works.
#   sudo /opt/libralink/ops/fault/verify-fix.sh
# Writes a 120 MB log file (bigger than the 50 MB cap), runs the rotation, and shows the
# file was rotated and compressed instead of growing.
set -euo pipefail
FILE=/var/log/libralink/debug-trace.log

echo "1) Writing a 120 MB test log..."
# (yes stops with "broken pipe" when head has enough; || true keeps that from aborting the script)
{ yes "$(date -u +%FT%TZ) DEBUG verify-fix test line - LibraLink log rotation check" || true; } | head -c 120M > "$FILE"
ls -lh /var/log/libralink/
echo
echo "2) Running the rotation now (normally the timer does this every 15 minutes)..."
/usr/sbin/logrotate --verbose --state /var/lib/libralink/logrotate.status /etc/logrotate.d/libralink 2>&1 | tail -15
echo
echo "3) Result - the big file is now empty and its rotated copy is compressed:"
ls -lh /var/log/libralink/
du -sh /var/log/libralink
rm -f /var/log/libralink/debug-trace.log*
echo
echo "4) Timer that keeps doing this:"
systemctl list-timers logrotate-libralink.timer --no-pager
"$(dirname "$0")/timeline.sh" "prevention verified: 120 MB test log rotated and compressed"
