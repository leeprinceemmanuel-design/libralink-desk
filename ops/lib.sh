#!/usr/bin/env bash
# Shared helpers for the scripts that run ON the EC2 server.
# Nothing here prints secret values.

LL_ROOT="${LL_ROOT:-/opt/libralink}"
LL_LOG_DIR=/var/log/libralink
LL_STATE_DIR=/var/lib/libralink
PARAM_PREFIX="${PARAM_PREFIX:-/libralink}"

# Region of this instance, from the instance metadata service (IMDSv2 token required).
ll_region() {
  if [[ -n "${AWS_REGION:-}" ]]; then echo "$AWS_REGION"; return; fi
  local token
  token=$(curl -s -m 3 -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 300")
  curl -s -m 3 -H "X-aws-ec2-metadata-token: $token" http://169.254.169.254/latest/meta-data/placement/region
}

# Export every parameter under a Parameter Store path as an environment variable.
#   ll_load_params config        -> /libralink/config/*  (plain settings)
#   ll_load_params secret        -> /libralink/secret/*  (SecureString, decrypted in memory only)
ll_load_params() {
  local sub="$1" region json
  region=$(ll_region)
  json=$(aws ssm get-parameters-by-path --region "$region" --path "$PARAM_PREFIX/$sub" \
           --recursive --with-decryption --output json)
  # Turn {"Parameters":[{"Name":"/libralink/config/BUCKET","Value":"x"}]} into NAME<TAB>VALUE lines.
  while IFS=$'\t' read -r name value; do
    [[ -z "$name" ]] && continue
    export "$name=$value"
  done < <(python3 -c '
import json, sys
for p in json.load(sys.stdin)["Parameters"]:
    print(p["Name"].rsplit("/", 1)[-1] + "\t" + p["Value"].replace("\t", " ").replace("\n", " "))
' <<<"$json")
}

# One JSON line per automation run, picked up by the CloudWatch agent (/libralink/automation).
# Usage: ll_log_job <job> <result> [extra json fields without braces]
ll_log_job() {
  local job="$1" result="$2" extra="${3:-}"
  mkdir -p "$LL_LOG_DIR"
  local line="{\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"host\":\"$(hostname -s)\",\"job\":\"$job\",\"result\":\"$result\"${extra:+,$extra}}"
  echo "$line" >> "$LL_LOG_DIR/automation.log"
  echo "$line"
}
