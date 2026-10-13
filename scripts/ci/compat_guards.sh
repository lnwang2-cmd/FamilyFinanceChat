#!/usr/bin/env bash
# CI compatibility guards: enforces the upstream-compatibility policy
# (see capstone_fall2026/). Run locally: bash scripts/ci/compat_guards.sh
# The gitleaks secret scan runs as its own job in .github/workflows/compat-guards.yml.
set -uo pipefail
fail=0
err() { echo "::error::$1"; fail=1; }

# Tracked files only, skipping reference-only folders
files() { git ls-files | grep -vE '^(legacy|archive)/'; }
COMPOSE=$(files | grep -E '(^|/)(docker-)?compose[^/]*\.ya?ml$')
DOCKERFILES=$(files | grep -E '(^|/)Dockerfile[^/]*$')

# 1. No mounts into Open WebUI's code or built frontend
for f in $COMPOSE; do
  grep -nE '(:|target:\s*)/app/(backend/open_webui|build)\b' "$f" \
    && err "$f mounts into /app/backend/open_webui or /app/build"
done

# 2. Open WebUI must run the official image (no custom builds)
for f in $COMPOSE; do
  grep -nE '^\s*image:.*open-webui' "$f" | grep -vE 'image:\s*["'\'']?ghcr\.io/open-webui/open-webui:' \
    && err "$f: Open WebUI image is not ghcr.io/open-webui/open-webui"
done
if [ -f Dockerfile ]; then
  grep -iE '^\s*FROM\s' Dockerfile | grep -viE '^\s*FROM\s+ghcr\.io/open-webui/open-webui:' \
    && err "Dockerfile: base image is not ghcr.io/open-webui/open-webui"
fi

# 3. No direct SQLite/SQLAlchemy access to Open WebUI's data directory
for f in $(files | grep '\.py$'); do
  if grep -qE 'sqlite3\.connect|create_engine|sessionmaker' "$f" \
     && grep -qE 'webui\.db|/app/backend/data|openwebui/data' "$f"; then
    err "$f opens a database in Open WebUI's data directory"
  fi
done

# 5. No floating :latest image tags (check 4, gitleaks, runs in the workflow)
for f in $COMPOSE $DOCKERFILES; do
  grep -inE '^\s*(image:|FROM)\s+\S+:latest["'\'']?\s*(#.*)?$' "$f" && err "$f uses a :latest image tag"
done

[ "$fail" -eq 0 ] && echo "All compatibility guards passed."
exit "$fail"
