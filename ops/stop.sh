#!/usr/bin/env bash
# Stops the LibraLink Desk containers (data in app/data/ is kept).
set -euo pipefail
source "$(dirname "$0")/lib.sh"
cd "$LL_ROOT/app"
# Compose needs the variables to exist to parse the file; real values are not needed to stop.
GOOGLE_MODEL=x GOOGLE_KEY=x CREDS_KEY=x CREDS_IV=x JWT_SECRET=x JWT_REFRESH_SECRET=x AWS_REGION=$(ll_region) \
  docker compose -f docker-compose.yml -f docker-compose.aws.yml down
ll_log_job stop ok
