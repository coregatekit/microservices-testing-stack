#!/usr/bin/env bash
set -euo pipefail

psql -v ON_ERROR_STOP=1 \
  --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
  -v app_pw="$NOTIFICATION_SERVICE_PASSWORD" <<'SQL'
CREATE ROLE notification_service LOGIN PASSWORD :'app_pw';

CREATE DATABASE notification OWNER migrator;
REVOKE ALL ON DATABASE notification FROM PUBLIC;
GRANT CONNECT ON DATABASE notification TO notification_service;

\connect notification

ALTER DEFAULT PRIVILEGES FOR ROLE migrator IN SCHEMA public
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO notification_service;
ALTER DEFAULT PRIVILEGES FOR ROLE migrator IN SCHEMA public
  GRANT USAGE, SELECT ON SEQUENCES TO notification_service;
SQL
