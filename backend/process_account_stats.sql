SET ROLE hafbe_owner;

CREATE OR REPLACE FUNCTION hafbe_backend.process_create_account_operation(_body jsonb, _timestamp timestamp, _op_type int)
RETURNS void
LANGUAGE 'plpgsql' VOLATILE
AS
$$
BEGIN
WITH create_account_operation AS (
  SELECT
    (SELECT av.id FROM hafbe_app.accounts_view av WHERE av.name = _body->'value'->>'new_account_name') AS _account,
    _timestamp AS _time,
    _op_type AS _op_type_id
)
  INSERT INTO hafbe_app.account_parameters
  (
    account,
    created,
    mined
  ) 
  SELECT
    _account,
    _time,
    FALSE
  FROM create_account_operation
  ON CONFLICT ON CONSTRAINT pk_account_parameters
  DO NOTHING;

END
$$;

CREATE OR REPLACE FUNCTION hafbe_backend.process_created_account_operation(_body jsonb, _timestamp timestamp, _if_hf11 boolean)
RETURNS void
LANGUAGE 'plpgsql' VOLATILE
AS
$$
DECLARE
  _recovery_account TEXT := _body->'value'->>'creator';
  _new_account_name TEXT := _body->'value'->>'new_account_name';
  _new_account INT := (SELECT av.id FROM hafbe_app.accounts_view av WHERE av.name = _body->'value'->>'new_account_name');
BEGIN

IF _if_hf11 THEN

  INSERT INTO hafbe_app.account_parameters
  (
    account,
    created,
    recovery_account
  ) 
  SELECT
    _new_account,
    _timestamp,
    (CASE WHEN _recovery_account = _new_account_name OR _recovery_account = 'temp' THEN
     ''
     ELSE
     _recovery_account
     END
    )

  ON CONFLICT ON CONSTRAINT pk_account_parameters
  DO UPDATE SET
    created = EXCLUDED.created,
    recovery_account = EXCLUDED.recovery_account;

ELSE

  INSERT INTO hafbe_app.account_parameters
  (
    account,
    created,
    recovery_account
  ) 
  SELECT
    _new_account,
    _timestamp,
    'steem'

  ON CONFLICT ON CONSTRAINT pk_account_parameters
  DO UPDATE SET
    created = EXCLUDED.created,
    recovery_account = EXCLUDED.recovery_account;

END IF;

END
$$;

CREATE OR REPLACE FUNCTION hafbe_backend.process_pow_operation(_body jsonb, _timestamp timestamp, _op_type int)
RETURNS void
LANGUAGE 'plpgsql' VOLATILE
AS
$$
BEGIN
WITH pow_operation AS (
  SELECT
    CASE WHEN _op_type = 14 THEN
    (SELECT av.id FROM hafbe_app.accounts_view av WHERE av.name = _body->'value'->>'worker_account')
    ELSE
    (SELECT av.id FROM hafbe_app.accounts_view av WHERE av.name = _body->'value'->'work'->'value'->'input'->>'worker_account')
    END AS _account,
    _timestamp AS _time
)
  INSERT INTO hafbe_app.account_parameters
  (
    account,
    created,
    mined
  ) 
  SELECT
    _account,
    _time,
    TRUE
  FROM pow_operation

  ON CONFLICT ON CONSTRAINT pk_account_parameters
  DO NOTHING
;
END
$$;

CREATE OR REPLACE FUNCTION hafbe_backend.process_changed_recovery_account_operation(_body jsonb)
RETURNS void
LANGUAGE 'plpgsql' VOLATILE
AS
$$
BEGIN
WITH changed_recovery_account_operation AS (
  SELECT
    (SELECT av.id FROM hafbe_app.accounts_view av WHERE av.name = _body->'value'->>'account') AS _account,
    _body->'value'->>'new_recovery_account' AS _new_recovery_account
)
  INSERT INTO hafbe_app.account_parameters
  (
    account,
    recovery_account
  ) 
  SELECT
    _account,
    _new_recovery_account
  FROM changed_recovery_account_operation

  ON CONFLICT ON CONSTRAINT pk_account_parameters
  DO UPDATE SET
    recovery_account = EXCLUDED.recovery_account;

END
$$;

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

RESET ROLE;
