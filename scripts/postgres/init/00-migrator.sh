#!/usr/bin/env bash
set -euo pipefail

# Shared role that runs schema migrations for every service and owns each service database.
psql -v ON_ERROR_STOP=1 \
  --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
  -v migrator_pw="$MIGRATOR_PASSWORD" <<'SQL'
CREATE ROLE migrator LOGIN PASSWORD :'migrator_pw';
SQL
