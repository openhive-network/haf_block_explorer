SET ROLE hafbe_owner;

CREATE OR REPLACE FUNCTION hafbe_app.process_create_account_operation(_body jsonb, _timestamp timestamp, _op_type int)
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

CREATE OR REPLACE FUNCTION hafbe_app.process_created_account_operation(_body jsonb, _timestamp timestamp, _if_hf11 boolean)
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

CREATE OR REPLACE FUNCTION hafbe_app.process_pow_operation(_body jsonb, _timestamp timestamp, _op_type int)
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

CREATE OR REPLACE FUNCTION hafbe_app.process_changed_recovery_account_operation(_body jsonb)
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

CREATE OR REPLACE FUNCTION hafbe_app.process_recover_account_operation(_body jsonb, _timestamp timestamp)
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

CREATE OR REPLACE FUNCTION hafbe_app.process_decline_voting_rights_operation(_body jsonb)
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

CREATE OR REPLACE FUNCTION hafbe_app.process_vote_op(_body jsonb, _timestamp timestamp)
RETURNS void
LANGUAGE 'plpgsql' VOLATILE
AS
$$
BEGIN
WITH vote_operation AS (
  SELECT
    (SELECT av.id FROM hafbe_app.accounts_view av WHERE av.name = _body->'value'->>'account') AS voter_id,
    (SELECT av.id FROM hafbe_app.accounts_view av WHERE av.name = _body->'value'->>'witness') AS witness_id,
    (_body->'value'->>'approve')::BOOLEAN AS approve,
    _timestamp AS _time
),
insert_votes_history AS (
  INSERT INTO hafbe_app.witness_votes_history (witness_id, voter_id, approve, timestamp)
  SELECT witness_id, voter_id, approve, _time
  FROM vote_operation
),
insert_current_votes AS (
  INSERT INTO hafbe_app.current_witness_votes (witness_id, voter_id, timestamp)
  SELECT witness_id, voter_id, _time
  FROM vote_operation
  WHERE approve IS TRUE
  ON CONFLICT ON CONSTRAINT pk_current_witness_votes DO UPDATE SET
    timestamp = EXCLUDED.timestamp
)

DELETE FROM hafbe_app.current_witness_votes cwv USING (
  SELECT witness_id, voter_id
  FROM vote_operation
  WHERE approve IS FALSE
) svo
WHERE cwv.witness_id = svo.witness_id AND cwv.voter_id = svo.voter_id;

END
$$;

CREATE OR REPLACE FUNCTION hafbe_app.process_proxy_ops(_body jsonb, _timestamp timestamp, _op_type int)
RETURNS void
LANGUAGE 'plpgsql' VOLATILE
AS
$$
BEGIN
WITH proxy_operations AS (
  SELECT
    _body->'value'->>'account' AS witness_account,
    _body->'value'->>'proxy' AS proxy_account,
    CASE WHEN _op_type = 13 THEN TRUE ELSE FALSE END AS proxy,
    _timestamp AS _time
),
selected AS (
    SELECT av_a.id AS account_id, av_p.id AS proxy_id, proxy, _time
    FROM proxy_operations proxy_op
    JOIN hafbe_app.accounts_view av_a ON av_a.name = proxy_op.witness_account
    JOIN hafbe_app.accounts_view av_p ON av_p.name = proxy_op.proxy_account
),
insert_proxy_history AS (
  INSERT INTO hafbe_app.account_proxies_history (account_id, proxy_id, proxy, timestamp)
  SELECT account_id, proxy_id, proxy, _time
  FROM selected
),
insert_current_proxies AS (
  INSERT INTO hafbe_app.current_account_proxies (account_id, proxy_id)
  SELECT account_id, proxy_id
  FROM selected
  WHERE proxy IS TRUE 
  ON CONFLICT ON CONSTRAINT pk_current_account_proxies DO UPDATE SET
    proxy_id = EXCLUDED.proxy_id
),
delete_votes_if_proxy AS (
  DELETE FROM hafbe_app.current_witness_votes cap USING (
    SELECT account_id 
    FROM selected
    WHERE proxy IS TRUE
  ) spo
  WHERE cap.voter_id = spo.account_id
)
DELETE FROM hafbe_app.current_account_proxies cap USING (
  SELECT account_id, proxy_id
  FROM selected
  WHERE proxy IS FALSE
) spo
WHERE cap.account_id = spo.account_id AND cap.proxy_id = spo.proxy_id
;

END
$$;

CREATE OR REPLACE FUNCTION hafbe_app.process_expired_accounts(_body jsonb)
RETURNS void
LANGUAGE 'plpgsql' VOLATILE
AS
$$
BEGIN
WITH proxy_operations AS (
  SELECT
    (SELECT av.id FROM hafbe_app.accounts_view av WHERE av.name = _body->'value'->>'account') AS account_id
),
delete_proxies AS (
  DELETE FROM hafbe_app.current_account_proxies cap USING (
    SELECT account_id 
    FROM proxy_operations
  ) spo
  WHERE cap.account_id = spo.account_id
)
DELETE FROM hafbe_app.current_witness_votes cap USING (
  SELECT account_id 
  FROM proxy_operations
) spoo
WHERE cap.voter_id = spoo.account_id;

END
$$;

RESET ROLE;
