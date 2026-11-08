#!/usr/bin/env bash
# Stop the local copy of LibraLink Desk (your local chats stay in app/data/).
set -euo pipefail
cd "$(dirname "$0")/../.."
GOOGLE_MODEL=x GOOGLE_KEY=x CREDS_KEY=x CREDS_IV=x JWT_SECRET=x JWT_REFRESH_SECRET=x \
  docker compose -f app/docker-compose.yml down
