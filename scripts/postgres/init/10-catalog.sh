#!/usr/bin/env bash
set -euo pipefail

psql -v ON_ERROR_STOP=1 \
  --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
  -v app_pw="$CATALOG_SERVICE_PASSWORD" <<'SQL'
CREATE ROLE catalog_service LOGIN PASSWORD :'app_pw';

CREATE DATABASE catalog OWNER migrator;
REVOKE ALL ON DATABASE catalog FROM PUBLIC;
GRANT CONNECT ON DATABASE catalog TO catalog_service;

\connect catalog

ALTER DEFAULT PRIVILEGES FOR ROLE migrator IN SCHEMA public
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO catalog_service;
ALTER DEFAULT PRIVILEGES FOR ROLE migrator IN SCHEMA public
  GRANT USAGE, SELECT ON SEQUENCES TO catalog_service;
SQL
