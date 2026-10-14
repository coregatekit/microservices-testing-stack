#!/usr/bin/env bash
set -euo pipefail

psql -v ON_ERROR_STOP=1 \
  --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
  -v app_pw="$BOOKING_SERVICE_PASSWORD" <<'SQL'
CREATE ROLE booking_service LOGIN PASSWORD :'app_pw';

CREATE DATABASE booking OWNER migrator;
REVOKE ALL ON DATABASE booking FROM PUBLIC;
GRANT CONNECT ON DATABASE booking TO booking_service;

\connect booking

ALTER DEFAULT PRIVILEGES FOR ROLE migrator IN SCHEMA public
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO booking_service;
ALTER DEFAULT PRIVILEGES FOR ROLE migrator IN SCHEMA public
  GRANT USAGE, SELECT ON SEQUENCES TO booking_service;
SQL
