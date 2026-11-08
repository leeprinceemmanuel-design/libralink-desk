#!/usr/bin/env bash
# WS-F FAULT INJECTION: fill the root disk to simulate a runaway, never-rotated log file.
# Safe inside your own account; undo with ops/fault/apply-fix.sh (or just delete the file).
#
#   sudo /opt/libralink/ops/fault/fill-disk.sh
#
# It writes one huge file into /var/log/libralink/ (the folder that has no log rotation yet)
# and leaves about 20 MB free, so the database can no longer save new chats.
set -euo pipefail
FILE=/var/log/libralink/debug-trace.log
LEAVE_MB="${LEAVE_MB:-20}"

echo "This will fill the root disk to ~100% (leaving ${LEAVE_MB} MB)."
echo "The app WILL break until you run ops/fault/apply-fix.sh."
read -r -p "Type FILL to continue: " ok
[[ "$ok" == "FILL" ]] || { echo "Cancelled."; exit 1; }

"$(dirname "$0")/timeline.sh" "fault started: filling / with $FILE"
echo "Disk before:"; df -h /

avail=$(df --output=avail -B1 / | tail -1)
size=$(( avail - LEAVE_MB * 1024 * 1024 ))
fallocate -l "$size" "$FILE"

echo "Disk after:"; df -h /
echo
echo "Now: wait for the disk alarm email (about 3-5 minutes), and try asking the assistant a question."
echo "When the email arrives, run:  sudo $(dirname "$0")/timeline.sh \"noticed: disk alarm email received\""
