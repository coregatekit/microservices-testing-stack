#!/usr/bin/env bash
set -euo pipefail

psql -v ON_ERROR_STOP=1 \
  --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
  -v app_pw="$PARTNER_SERVICE_PASSWORD" <<'SQL'
CREATE ROLE partner_service LOGIN PASSWORD :'app_pw';

CREATE DATABASE partner OWNER migrator;
REVOKE ALL ON DATABASE partner FROM PUBLIC;
GRANT CONNECT ON DATABASE partner TO partner_service;

-- Unqualified names resolve to the service schema for both roles.
ALTER ROLE migrator        IN DATABASE partner SET search_path = partner;
ALTER ROLE partner_service IN DATABASE partner SET search_path = partner;

\connect partner

DROP SCHEMA public;
CREATE SCHEMA partner AUTHORIZATION migrator;
GRANT USAGE ON SCHEMA partner TO partner_service;

ALTER DEFAULT PRIVILEGES FOR ROLE migrator IN SCHEMA partner
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO partner_service;
ALTER DEFAULT PRIVILEGES FOR ROLE migrator IN SCHEMA partner
  GRANT USAGE, SELECT ON SEQUENCES TO partner_service;
SQL
