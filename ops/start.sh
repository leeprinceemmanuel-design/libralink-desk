#!/usr/bin/env bash
# Starts LibraLink Desk on the EC2 server. Run by systemd (libralink.service) at boot,
# or by hand:  sudo systemctl restart libralink
#
# 1. reads settings + secrets from Parameter Store (secrets stay in memory, never written to disk)
# 2. downloads the handbook from S3
# 3. builds librechat.yaml from the handbook
# 4. starts the Docker stack
set -euo pipefail
source "$(dirname "$0")/lib.sh"

start=$(date +%s)
export AWS_REGION; AWS_REGION=$(ll_region)

ll_load_params config      # BUCKET, GOOGLE_MODEL, APP_VERSION, LIBRECHAT_IMAGE, PUBLIC_URL, SITE_URL, SNS_TOPIC_ARN
ll_load_params secret      # GOOGLE_KEY, CREDS_KEY, CREDS_IV, JWT_SECRET, JWT_REFRESH_SECRET
: "${BUCKET:?BUCKET parameter missing}" "${GOOGLE_KEY:?GOOGLE_KEY parameter missing}"

# Handbook content lives in S3 (versioned), not inside the Docker image.
mkdir -p "$LL_ROOT/run/content"
aws s3 sync "s3://$BUCKET/content/" "$LL_ROOT/run/content/" --delete --only-show-errors --region "$AWS_REGION"

python3 "$LL_ROOT/ops/render_config.py" \
  --content "$LL_ROOT/run/content" \
  --model "$GOOGLE_MODEL" \
  --site "${SITE_URL:-$PUBLIC_URL}" \
  --app-version "${APP_VERSION:-v1.0}"

# Folders the containers write to. LibreChat runs as uid 1000 (ec2-user).
mkdir -p "$LL_ROOT/app/data/"{uploads,images,logs,mongo} "$LL_LOG_DIR/nginx"
chown -R 1000:1000 "$LL_ROOT/app/data/uploads" "$LL_ROOT/app/data/images" "$LL_ROOT/app/data/logs"

# (UID/GID are left unset on purpose: bash's UID is read-only, and compose then uses its default 1000.)
export NGINX_LOG_DIR="$LL_LOG_DIR/nginx" HTTP_PORT=80
export LIBRECHAT_IMAGE PUBLIC_URL SITE_URL GOOGLE_MODEL
export GOOGLE_KEY CREDS_KEY CREDS_IV JWT_SECRET JWT_REFRESH_SECRET

cd "$LL_ROOT/app"
docker compose -f docker-compose.yml -f docker-compose.aws.yml up -d --remove-orphans
# nginx looks up LibreChat's container address once; reload it in case that container was recreated.
sleep 3; docker exec libralink-nginx nginx -s reload >/dev/null 2>&1 || true

ver=$(python3 -c 'import json;d=json.load(open("'"$LL_ROOT"'/run/version.json"));print(d["app_version"]+"/"+d["content_hash"])')
ll_log_job start ok "\"seconds\":$(( $(date +%s) - start )),\"version\":\"$ver\",\"image\":\"$LIBRECHAT_IMAGE\""
