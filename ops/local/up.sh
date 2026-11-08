#!/usr/bin/env bash
# Run LibraLink Desk on YOUR LAPTOP (WS-A item 1: "running locally").
# Needs: Docker Desktop running. On Windows, run this from Git Bash.
#
#   bash ops/local/up.sh
#   then open http://localhost:8080
#
# It asks for your Gemini API key (typing is hidden) and makes fresh random
# encryption keys each time. Nothing secret is written to disk.
set -euo pipefail
cd "$(dirname "$0")/../.."
export MSYS_NO_PATHCONV=1   # stops Git Bash on Windows from rewriting the /w path below

if [[ -z "${GOOGLE_KEY:-}" ]]; then
  read -r -s -p "Paste your Gemini API key (hidden): " GOOGLE_KEY; echo
fi
export GOOGLE_KEY
export GOOGLE_MODEL="${GOOGLE_MODEL:-gemini-2.5-flash}"
export LIBRECHAT_IMAGE="${LIBRECHAT_IMAGE:-ghcr.io/danny-avila/librechat:latest}"
export PUBLIC_URL=http://localhost:8080 SITE_URL=http://localhost:8080 HTTP_PORT=8080

rand() { docker run --rm alpine:3.20 sh -c "head -c $1 /dev/urandom | od -An -tx1 | tr -d ' \n'"; }
export CREDS_KEY; CREDS_KEY=$(rand 32)
export CREDS_IV; CREDS_IV=$(rand 16)
export JWT_SECRET; JWT_SECRET=$(rand 32)
export JWT_REFRESH_SECRET; JWT_REFRESH_SECRET=$(rand 32)

# Build librechat.yaml from the handbook in content/ (uses a throw-away Python container).
docker run --rm -v "$PWD":/w -w /w python:3.12-alpine \
  python ops/render_config.py --content content --model "$GOOGLE_MODEL" --site "$SITE_URL" --app-version local

mkdir -p app/data/{uploads,images,logs,mongo,nginx-logs}
docker compose -f app/docker-compose.yml up -d

echo
echo "Starting... give it about a minute, then open http://localhost:8080"
echo "Create your login (first time only):  docker exec -it LibreChat npm run create-user"
echo "Stop it later:                       bash ops/local/down.sh"
