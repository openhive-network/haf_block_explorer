SET ROLE hafbe_owner;

DROP TYPE IF EXISTS hafbe_backend.impacted_account_parameters CASCADE;
CREATE TYPE hafbe_backend.impacted_account_parameters AS
(
    account_name TEXT,
    mined BOOLEAN,
    recovery_account TEXT,
    created TIMESTAMP
);

CREATE OR REPLACE FUNCTION hafbe_backend.get_impacted_account_parameters(IN _operation_body JSONB, IN _op_type_id INT, _timestamp TIMESTAMP, _if_hf11 BOOLEAN)
RETURNS hafbe_backend.impacted_account_parameters
LANGUAGE plpgsql
STABLE
AS
$BODY$
BEGIN
  RETURN (
    CASE 
      WHEN _op_type_id = 14 THEN
        hafbe_backend.process_pow_operation(_operation_body, _timestamp) -- on conflict do nothing

      WHEN _op_type_id = 30 THEN
        hafbe_backend.process_pow_two_operation(_operation_body, _timestamp) -- on conflict do nothing

      WHEN _op_type_id = 80 THEN
        hafbe_backend.process_created_account_operation(_operation_body, _timestamp, _if_hf11) -- on conflict upsert

      WHEN _op_type_id = 9 OR _op_type_id = 23 OR _op_type_id = 41 THEN -- on conflict do nothing
        hafbe_backend.process_create_account_operation(_operation_body, _timestamp)

      WHEN _op_type_id = 76 THEN
        hafbe_backend.process_changed_recovery_account_operation(_operation_body)
    END
  );

END;
$BODY$;


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

--------------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION hafbe_backend.process_recover_account_operation(IN _operation_body JSONB)
RETURNS TEXT
LANGUAGE 'plpgsql' STABLE
AS
$$
BEGIN
  RETURN _operation_body->'value'->>'account_to_recover';
END
$$;

/*
CREATE OR REPLACE FUNCTION hafbe_backend.process_recover_account_operation(_body jsonb, _timestamp timestamp)
RETURNS void
LANGUAGE 'plpgsql' VOLATILE
AS
$$
BEGIN
WITH recover_account_operation AS (
  SELECT
    (SELECT av.id FROM hafbe_app.accounts_view av WHERE av.name = _body->'value'->>'account_to_recover') AS _account,
    _timestamp AS _time
)
  INSERT INTO hafbe_app.account_parameters
  (
    account,
    last_account_recovery
  ) 
  SELECT
    _account,
    _time
  FROM recover_account_operation

  ON CONFLICT ON CONSTRAINT pk_account_parameters
  DO UPDATE SET
    last_account_recovery = EXCLUDED.last_account_recovery;

END
$$;
*/

--------------------------------------------------------------------------------------------------------------------------

DROP TYPE IF EXISTS hafbe_backend.impacted_account_voting_rights CASCADE;
CREATE TYPE hafbe_backend.impacted_account_voting_rights AS
(
    account_name TEXT,
    can_vote BOOLEAN
);

CREATE OR REPLACE FUNCTION hafbe_backend.process_decline_voting_rights_operation(IN _operation_body JSONB)
RETURNS hafbe_backend.impacted_account_voting_rights
LANGUAGE 'plpgsql' STABLE
AS
$$
BEGIN
  RETURN (
    _operation_body->'value'->>'account',
    (
      CASE 
        WHEN (_operation_body->'value'->>'decline')::BOOLEAN = TRUE THEN
          FALSE 
        ELSE 
          TRUE 
      END
  )
  )::hafbe_backend.impacted_account_voting_rights;
END
$$;

/*
CREATE OR REPLACE FUNCTION hafbe_backend.process_decline_voting_rights_operation(_body jsonb)
RETURNS void
LANGUAGE 'plpgsql' VOLATILE
AS
$$
BEGIN
WITH decline_voting_rights_operation AS (
  SELECT
    (SELECT av.id FROM hafbe_app.accounts_view av WHERE av.name = _body->'value'->>'account') AS _account,
    (CASE WHEN (_body->'value'->>'decline')::BOOLEAN = TRUE THEN FALSE ELSE TRUE END) AS _can_vote
)
  INSERT INTO hafbe_app.account_parameters
  (
    account,
    can_vote
  ) 
  SELECT
    _account,
    _can_vote
  FROM decline_voting_rights_operation

  ON CONFLICT ON CONSTRAINT pk_account_parameters
  DO UPDATE SET
    can_vote = EXCLUDED.can_vote;

END
$$;
*/

--------------------------------------------------------------------------------------------------------------------------

RESET ROLE;
