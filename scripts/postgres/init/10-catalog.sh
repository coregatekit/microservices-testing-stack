#!/usr/bin/env bash
set -euo pipefail

psql -v ON_ERROR_STOP=1 \
  --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
  -v app_pw="$CATALOG_SERVICE_PASSWORD" <<'SQL'
CREATE ROLE catalog_service LOGIN PASSWORD :'app_pw';

CREATE DATABASE catalog OWNER migrator;
REVOKE ALL ON DATABASE catalog FROM PUBLIC;
GRANT CONNECT ON DATABASE catalog TO catalog_service;

-- Unqualified names resolve to the service schema for both roles.
ALTER ROLE migrator        IN DATABASE catalog SET search_path = catalog;
ALTER ROLE catalog_service IN DATABASE catalog SET search_path = catalog;

\connect catalog

DROP SCHEMA public;
CREATE SCHEMA catalog AUTHORIZATION migrator;
GRANT USAGE ON SCHEMA catalog TO catalog_service;

ALTER DEFAULT PRIVILEGES FOR ROLE migrator IN SCHEMA catalog
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO catalog_service;
ALTER DEFAULT PRIVILEGES FOR ROLE migrator IN SCHEMA catalog
  GRANT USAGE, SELECT ON SEQUENCES TO catalog_service;
SQL
