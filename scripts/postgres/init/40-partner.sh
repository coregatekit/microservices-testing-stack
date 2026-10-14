#!/usr/bin/env bash
set -euo pipefail

psql -v ON_ERROR_STOP=1 \
  --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
  -v app_pw="$PARTNER_SERVICE_PASSWORD" <<'SQL'
CREATE ROLE partner_service LOGIN PASSWORD :'app_pw';

CREATE DATABASE partner OWNER migrator;
REVOKE ALL ON DATABASE partner FROM PUBLIC;
GRANT CONNECT ON DATABASE partner TO partner_service;

\connect partner

ALTER DEFAULT PRIVILEGES FOR ROLE migrator IN SCHEMA public
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO partner_service;
ALTER DEFAULT PRIVILEGES FOR ROLE migrator IN SCHEMA public
  GRANT USAGE, SELECT ON SEQUENCES TO partner_service;
SQL
