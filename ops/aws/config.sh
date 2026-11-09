#!/usr/bin/env bash
# Shared settings for the ops/aws/*.sh scripts. These run in AWS CloudShell
# signed in with your own AWS login (with MFA), so no access keys are ever created.
# Every script does:  source "$(dirname "$0")/config.sh"
set -euo pipefail

# Always Sydney. Our AWS Free-plan account is locked to ap-southeast-2: a test on 9 Nov 2026
# showed S3, Parameter Store, SNS, EC2 and Lambda all denied in Singapore (ap-southeast-1) and
# us-east-1, and allowed in Sydney. CloudShell sets AWS_REGION to whatever region the console
# shows, so we do NOT reuse it; set LL_REGION only if you really want another region.
export AWS_REGION="${LL_REGION:-ap-southeast-2}"
export AWS_DEFAULT_REGION="$AWS_REGION"
export AWS_PAGER=""

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export ACCOUNT_ID

export PROJECT=SAM10 TEAM=libralink
export BUCKET="libralink-content-$ACCOUNT_ID"          # handbook content + backups (versioned)
export TRAIL_BUCKET="libralink-cloudtrail-$ACCOUNT_ID"
export TOPIC_NAME=libralink-alerts
export INSTANCE_NAME=libralink-server
export INSTANCE_TYPE="${INSTANCE_TYPE:-t3.small}"   # Free plan allows only Free Tier sizes (t3.small = 2 GB)
export PARAM_PREFIX=/libralink
export LOG_GROUPS="/libralink/app /libralink/mongodb /libralink/requests /libralink/nginx /libralink/automation /libralink/healthcheck"

# Tags on everything, so the bill can be traced (brief section 6.2).
export TAGS_KV="Key=Project,Value=$PROJECT Key=Team,Value=$TEAM"
export TAGS_JSON='[{"Key":"Project","Value":"SAM10"},{"Key":"Team","Value":"libralink"}]'

# Small state file so later scripts know the IDs earlier scripts created (not committed to git).
STATE_FILE="$(dirname "${BASH_SOURCE[0]}")/.state"
touch "$STATE_FILE"
# shellcheck disable=SC1090
source "$STATE_FILE"
save_state() {  # save_state NAME VALUE
  grep -v "^export $1=" "$STATE_FILE" > "$STATE_FILE.tmp" || true
  echo "export $1=\"$2\"" >> "$STATE_FILE.tmp"
  mv "$STATE_FILE.tmp" "$STATE_FILE"
  export "$1=$2"
}

say() { printf '\n\033[1;36m== %s\033[0m\n' "$*"; }
