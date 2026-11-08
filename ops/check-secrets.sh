#!/usr/bin/env bash
# WS-D item 3 evidence: prove there are no keys in the code OR in the git history.
#   bash ops/check-secrets.sh
# Looks for: Google/Gemini keys (AIza...), AWS access keys (AKIA/ASIA...), private keys,
# OpenAI-style keys, and long hex values assigned to our secret names.
# Exit code 0 = clean, 1 = something found (rotate that key immediately and tell your instructor).
set -uo pipefail
cd "$(dirname "$0")/.."

PATTERN='AIza[0-9A-Za-z_-]{35}|(AKIA|ASIA)[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY-----|sk-[A-Za-z0-9_-]{20,}|(CREDS_KEY|CREDS_IV|JWT_SECRET|JWT_REFRESH_SECRET|GOOGLE_KEY)[=:][[:space:]]*["'"'"']?[0-9a-fA-F]{16,}'
found=0

echo "1) Files in the working folder:"
if grep -rInE "$PATTERN" --exclude-dir=.git --exclude-dir=data --exclude=check-secrets.sh . ; then
  found=1
else
  echo "   clean"
fi

echo "2) Every commit in the git history (including deleted files):"
if git rev-parse --git-dir >/dev/null 2>&1; then
  hits=$(git log --all -p --no-color -- . ':(exclude)ops/check-secrets.sh' | grep -nE "$PATTERN" || true)
  if [[ -n "$hits" ]]; then echo "$hits"; found=1; else echo "   clean ($(git rev-list --all --count) commits checked)"; fi
else
  echo "   (not a git repository yet)"
fi

[[ $found -eq 0 ]] && echo "RESULT: no secrets found." || echo "RESULT: POSSIBLE SECRET FOUND - see above."
exit $found
