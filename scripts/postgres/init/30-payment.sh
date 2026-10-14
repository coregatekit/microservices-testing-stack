#!/usr/bin/env bash
set -euo pipefail

psql -v ON_ERROR_STOP=1 \
  --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
  -v app_pw="$PAYMENT_SERVICE_PASSWORD" <<'SQL'
CREATE ROLE payment_service LOGIN PASSWORD :'app_pw';

CREATE DATABASE payment OWNER migrator;
REVOKE ALL ON DATABASE payment FROM PUBLIC;
GRANT CONNECT ON DATABASE payment TO payment_service;

-- Unqualified names resolve to the service schema for both roles.
ALTER ROLE migrator        IN DATABASE payment SET search_path = payment;
ALTER ROLE payment_service IN DATABASE payment SET search_path = payment;

\connect payment

DROP SCHEMA public;
CREATE SCHEMA payment AUTHORIZATION migrator;
GRANT USAGE ON SCHEMA payment TO payment_service;

ALTER DEFAULT PRIVILEGES FOR ROLE migrator IN SCHEMA payment
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO payment_service;
ALTER DEFAULT PRIVILEGES FOR ROLE migrator IN SCHEMA payment
  GRANT USAGE, SELECT ON SEQUENCES TO payment_service;
SQL
