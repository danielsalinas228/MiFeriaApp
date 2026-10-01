CREATE TABLE users (
  id                UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  email             TEXT        UNIQUE NOT NULL,
  password_hash     TEXT        NOT NULL,
  name              TEXT        NOT NULL,
  email_verified    BOOLEAN     NOT NULL DEFAULT false,
  base_currency     CHAR(3)     NOT NULL DEFAULT 'MXN',
  timezone          TEXT        NOT NULL DEFAULT 'UTC',
  period_start_day  SMALLINT    NOT NULL DEFAULT 1,
  deleted_at        TIMESTAMPTZ,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);
