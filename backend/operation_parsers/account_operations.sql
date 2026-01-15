SET ROLE hafbe_owner;

-- Type definition for account parameters
DROP TYPE IF EXISTS hafbe_backend.impacted_account_parameters CASCADE;
CREATE TYPE hafbe_backend.impacted_account_parameters AS
(
    account_name TEXT,
    mined BOOLEAN,
    recovery_account TEXT,
    created TIMESTAMP
);

-- Helper functions for parsing account creation/recovery operations
-- These are called via CASE WHEN in hafbe_app.process_account_stats()

CREATE OR REPLACE FUNCTION hafbe_backend.process_pow_operation(IN _operation_body JSONB, IN _timestamp TIMESTAMP)
RETURNS hafbe_backend.impacted_account_parameters
LANGUAGE 'plpgsql' STABLE
AS
$$
BEGIN
  RETURN (
    ((_operation_body)->'value'->>'worker_account')::TEXT,
    TRUE,
    NULL,
    _timestamp
  )::hafbe_backend.impacted_account_parameters;
END
$$;

CREATE OR REPLACE FUNCTION hafbe_backend.process_pow_two_operation(IN _operation_body JSONB, IN _timestamp TIMESTAMP)
RETURNS hafbe_backend.impacted_account_parameters
LANGUAGE 'plpgsql' STABLE
AS
$$
BEGIN
  RETURN (
    ((_operation_body)->'value'->'work'->'value'->'input'->>'worker_account')::TEXT,
    TRUE,
    NULL,
    _timestamp
  )::hafbe_backend.impacted_account_parameters;
END
$$;

CREATE OR REPLACE FUNCTION hafbe_backend.process_created_account_operation(IN _operation_body JSONB, IN _timestamp TIMESTAMP, IN _if_hf11 BOOLEAN)
RETURNS hafbe_backend.impacted_account_parameters
LANGUAGE 'plpgsql' STABLE
AS
$$
DECLARE
  _new_account_name TEXT := _operation_body->'value'->>'new_account_name';
  _creator          TEXT := _operation_body->'value'->>'creator';
  _recovery_account TEXT;
BEGIN
  _recovery_account := (
    CASE
      WHEN _if_hf11 AND (_creator = _new_account_name OR _creator = 'temp') THEN
        ''
      WHEN NOT _if_hf11 THEN
        'steem'
      ELSE
        _creator
    END
  );

  RETURN (
    _new_account_name,
    NULL,
    _recovery_account,
    _timestamp
  )::hafbe_backend.impacted_account_parameters;
END
$$;

CREATE OR REPLACE FUNCTION hafbe_backend.process_create_account_operation(IN _operation_body JSONB, IN _timestamp TIMESTAMP)
RETURNS hafbe_backend.impacted_account_parameters
LANGUAGE 'plpgsql' STABLE
AS
$$
BEGIN
  RETURN (
    _operation_body->'value'->>'new_account_name',
    FALSE,
    NULL,
    _timestamp
  )::hafbe_backend.impacted_account_parameters;
END
$$;

CREATE OR REPLACE FUNCTION hafbe_backend.process_changed_recovery_account_operation(IN _operation_body JSONB)
RETURNS hafbe_backend.impacted_account_parameters
LANGUAGE 'plpgsql' STABLE
AS
$$
BEGIN
  RETURN (
    _operation_body->'value'->>'account',
    NULL,
    _operation_body->'value'->>'new_recovery_account',
    NULL
  )::hafbe_backend.impacted_account_parameters;
END
$$;

RESET ROLE;
