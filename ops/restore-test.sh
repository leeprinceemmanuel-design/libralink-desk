#!/usr/bin/env bash
# WS-C restore test. Run on the server:  sudo /opt/libralink/ops/restore-test.sh [full|side] [s3-key]
#
#   side  (safe practice run): restores the latest backup into a throw-away MongoDB container
#         and compares document counts with the live database. Live system is untouched.
#   full  (the real test for the marks): stops the app, moves the live database folder aside,
#         starts an EMPTY database, restores the latest backup from S3, starts the app again.
#         Then you log in and check your old conversations are back.
#         Undo: see the "HOW TO UNDO" lines printed at the end.
#
# Prints timings, which are your measured RTO (recovery time).
set -euo pipefail
source "$(dirname "$0")/lib.sh"

mode="${1:-side}"
region=$(ll_region)
ll_load_params config
work="$LL_STATE_DIR/restore"; mkdir -p "$work"

count_docs() {  # $1 = container name
  docker exec "$1" mongosh LibreChat --quiet --eval \
    'print(JSON.stringify({users: db.users.countDocuments(), conversations: db.conversations.countDocuments(), messages: db.messages.countDocuments()}))'
}

t0=$(date +%s)
key="${2:-$(aws s3api list-objects-v2 --region "$region" --bucket "$BUCKET" --prefix backups/mongo/ \
              --query 'sort_by(Contents,&LastModified)[-1].Key' --output text)}"
[[ "$key" == "None" || -z "$key" ]] && { echo "No backups found in s3://$BUCKET/backups/mongo/"; exit 1; }
echo "== Using backup: s3://$BUCKET/$key"
aws s3 cp "s3://$BUCKET/$key" "$work/restore.archive.gz" --region "$region" --only-show-errors
t_download=$(date +%s)

echo "== Live database counts BEFORE:"
before=$(count_docs chat-mongodb); echo "$before"

if [[ "$mode" == "side" ]]; then
  docker rm -f ll-restore-test >/dev/null 2>&1 || true
  docker run -d --name ll-restore-test mongo:8.0 >/dev/null
  until docker exec ll-restore-test mongosh --quiet --eval 'db.runCommand({ping:1}).ok' >/dev/null 2>&1; do sleep 2; done
  docker exec -i ll-restore-test mongorestore --archive --gzip --quiet < "$work/restore.archive.gz"
  echo "== Restored copy counts:"
  after=$(count_docs ll-restore-test); echo "$after"
  docker rm -f ll-restore-test >/dev/null
else
  cd "$LL_ROOT/app"
  dc() { GOOGLE_MODEL=x GOOGLE_KEY=x CREDS_KEY=x CREDS_IV=x JWT_SECRET=x JWT_REFRESH_SECRET=x AWS_REGION=$region \
           docker compose -f docker-compose.yml -f docker-compose.aws.yml "$@"; }
  echo "== Stopping the app and moving the live database aside"
  systemctl stop libralink.service
  aside="data/mongo.before-restore-$(date -u +%Y%m%dT%H%M%SZ)"
  mv data/mongo "$aside"; mkdir -p data/mongo
  dc up -d mongodb
  until docker exec chat-mongodb mongosh --quiet --eval 'db.runCommand({ping:1}).ok' >/dev/null 2>&1; do sleep 2; done
  echo "== Empty database counts (should be 0):"; count_docs chat-mongodb
  docker exec -i chat-mongodb mongorestore --archive --gzip --quiet < "$work/restore.archive.gz"
  echo "== Restored database counts:"
  after=$(count_docs chat-mongodb); echo "$after"
  systemctl start libralink.service
  until curl -fs -o /dev/null http://localhost/health; do sleep 3; done
  echo
  echo "HOW TO UNDO (only if the restore looks wrong):"
  echo "  sudo systemctl stop libralink && cd $LL_ROOT/app && sudo rm -rf data/mongo && sudo mv $aside data/mongo && sudo systemctl start libralink"
  echo "When you are happy, free the disk space:  sudo rm -rf $LL_ROOT/app/$aside"
fi

t_done=$(date +%s)
rm -f "$work/restore.archive.gz"
echo
echo "== Timings: download $((t_download - t0))s, total restore $((t_done - t0))s  (mode: $mode)"
ll_log_job "restore-$mode" ok "\"key\":\"$key\",\"seconds\":$((t_done - t0)),\"before\":$before,\"after\":$after"
