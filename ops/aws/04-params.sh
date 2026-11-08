#!/usr/bin/env bash
# DAY 1, STEP 4 - settings and secrets in Systems Manager Parameter Store (WS-D item 3).
#   bash ops/aws/04-params.sh
# Plain settings  -> /libralink/config/*  (String)
# Secrets         -> /libralink/secret/*  (SecureString, encrypted with KMS)
# The Gemini key is typed in hidden, so it never appears on screen, in shell history or in git.
# Existing secrets are NOT overwritten (changing CREDS_KEY would break stored data).
source "$(dirname "$0")/config.sh"

GOOGLE_MODEL="${GOOGLE_MODEL:-gemini-2.5-flash}"
APP_VERSION="${APP_VERSION:-v1.0}"
LIBRECHAT_IMAGE="${LIBRECHAT_IMAGE:-ghcr.io/danny-avila/librechat:latest}"
SITE_URL="${SITE_URL:-https://example.github.io/libralink-desk}"

put_config() {  # name value
  aws ssm put-parameter --name "$PARAM_PREFIX/config/$1" --type String --value "$2" --overwrite >/dev/null
  aws ssm add-tags-to-resource --resource-type Parameter --resource-id "$PARAM_PREFIX/config/$1" --tags $TAGS_KV
  echo "  config/$1 = $2"
}
put_secret() {  # name value   (only if it does not exist yet)
  if aws ssm get-parameter --name "$PARAM_PREFIX/secret/$1" >/dev/null 2>&1; then
    echo "  secret/$1 already exists - left unchanged"; return
  fi
  aws ssm put-parameter --name "$PARAM_PREFIX/secret/$1" --type SecureString --value "$2" \
    --tags $TAGS_KV >/dev/null
  echo "  secret/$1 stored (SecureString)"
}

say "Settings"
put_config BUCKET "$BUCKET"
put_config GOOGLE_MODEL "$GOOGLE_MODEL"
put_config APP_VERSION "$APP_VERSION"
put_config LIBRECHAT_IMAGE "$LIBRECHAT_IMAGE"
put_config SITE_URL "$SITE_URL"
aws ssm get-parameter --name "$PARAM_PREFIX/config/PUBLIC_URL" >/dev/null 2>&1 \
  || put_config PUBLIC_URL "http://localhost"   # replaced by 07-cloudfront.sh

say "Secrets"
if ! aws ssm get-parameter --name "$PARAM_PREFIX/secret/GOOGLE_KEY" >/dev/null 2>&1; then
  read -r -s -p "Paste the Gemini API key (hidden, press Enter): " gk; echo
  [[ -n "$gk" ]] || { echo "No key entered."; exit 1; }
  put_secret GOOGLE_KEY "$gk"; unset gk
else
  echo "  secret/GOOGLE_KEY already exists - left unchanged (to replace it: see the runbook 'Rotate the Gemini key')"
fi
put_secret CREDS_KEY "$(openssl rand -hex 32)"           # 32 bytes, as LibreChat requires
put_secret CREDS_IV "$(openssl rand -hex 16)"            # 16 bytes
put_secret JWT_SECRET "$(openssl rand -hex 32)"
put_secret JWT_REFRESH_SECRET "$(openssl rand -hex 32)"

say "What is stored (names and types only - evidence E-13):"
aws ssm describe-parameters --parameter-filters "Key=Name,Option=BeginsWith,Values=$PARAM_PREFIX/" \
  --query 'Parameters[].[Name,Type,LastModifiedDate]' --output table
