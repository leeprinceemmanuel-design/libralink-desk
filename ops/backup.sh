#!/usr/bin/env bash
# AUTOMATION 1 - hourly backup (run by libralink-backup.timer, nobody touches it).
#   - dumps the MongoDB database (users, conversations, messages) and streams it to S3
#   - saves the LIST of Parameter Store settings (names, types, versions - never the values)
#   - writes one JSON line to /var/log/libralink/automation.log -> CloudWatch /libralink/automation
#   - on failure, emails the team through SNS
# S3 lifecycle rule (set by ops/aws/03-s3.sh) deletes backups after 8 days, so 7 full days are kept.
set -uo pipefail
source "$(dirname "$0")/lib.sh"

start=$(date +%s)
ts=$(date -u +%Y%m%dT%H%M%SZ)
region=$(ll_region)
ll_load_params config
key="backups/mongo/LibreChat-$ts.archive.gz"

fail() {
  ll_log_job backup fail "\"step\":\"$1\",\"seconds\":$(( $(date +%s) - start ))"
  [[ -n "${SNS_TOPIC_ARN:-}" ]] && aws sns publish --region "$region" --topic-arn "$SNS_TOPIC_ARN" \
    --subject "LibraLink backup FAILED ($1)" \
    --message "Backup failed at step '$1' on $(hostname) at $ts UTC. Check /var/log/libralink/automation.log." >/dev/null
  exit 1
}

# 1. Database dump, streamed straight to S3 (no copy left on the small server disk).
docker exec chat-mongodb mongodump --db LibreChat --archive --gzip --quiet \
  | aws s3 cp - "s3://$BUCKET/$key" --region "$region" --only-show-errors \
  || fail mongodump

bytes=$(aws s3api head-object --region "$region" --bucket "$BUCKET" --key "$key" \
          --query ContentLength --output text) || fail verify
[[ "$bytes" -gt 100 ]] || fail empty-dump

# 2. Configuration inventory: what would have to exist to rebuild (values are NOT copied).
aws ssm describe-parameters --region "$region" \
  --parameter-filters "Key=Name,Option=BeginsWith,Values=$PARAM_PREFIX/" \
  --query 'Parameters[].{Name:Name,Type:Type,Version:Version,LastModified:LastModifiedDate}' \
  --output json | aws s3 cp - "s3://$BUCKET/backups/config/parameters-$ts.json" \
  --region "$region" --only-show-errors || fail config-list

ll_log_job backup ok "\"key\":\"$key\",\"bytes\":$bytes,\"seconds\":$(( $(date +%s) - start ))"
