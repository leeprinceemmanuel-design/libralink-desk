#!/usr/bin/env bash
# Write one line to the incident timeline, in UTC and Manila time.
#   sudo /opt/libralink/ops/fault/timeline.sh "noticed: alarm email arrived"
# The timeline (and the alarm history) gives you time to detect and time to fix for the website.
set -euo pipefail
msg="${*:?usage: timeline.sh <what happened>}"
line="$(date -u +%Y-%m-%dT%H:%M:%SZ) | $(TZ=Asia/Manila date '+%Y-%m-%d %H:%M:%S PHT') | $msg"
echo "$line" | tee -a /var/log/libralink/incident-timeline.txt
