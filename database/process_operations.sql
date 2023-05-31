SET ROLE hafbe_owner;

CREATE OR REPLACE FUNCTION hafbe_app.process_create_account_operation(_body jsonb, _timestamp timestamp, _op_type int)
RETURNS void
LANGUAGE 'plpgsql' VOLATILE
AS
$$
BEGIN
WITH create_account_operation AS (
  SELECT
    (SELECT av.id FROM hive.hafbe_app_accounts_view av WHERE av.name = _body->'value'->>'new_account_name') AS _account,
    _timestamp AS _time,
    _op_type AS _op_type_id
),
insert_created_accounts AS (

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
  WHERE _op_type_id != 80

  ON CONFLICT ON CONSTRAINT pk_account_parameters
  DO NOTHING
)
    INSERT INTO hafbe_app.account_parameters
  (
    account,
    created
  ) 
  SELECT
    _account,
    _time
  FROM create_account_operation
  WHERE _op_type_id = 80

  ON CONFLICT ON CONSTRAINT pk_account_parameters
  DO NOTHING;


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
    (SELECT av.id FROM hive.hafbe_app_accounts_view av WHERE av.name = _body->'value'->>'worker_account')
    ELSE
    (SELECT av.id FROM hive.hafbe_app_accounts_view av WHERE av.name = _body->'value'->'work'->'value'->'input'->>'worker_account')
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
    (SELECT av.id FROM hive.hafbe_app_accounts_view av WHERE av.name = _body->'value'->>'account') AS _account,
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
    (SELECT av.id FROM hive.hafbe_app_accounts_view av WHERE av.name = _body->'value'->>'account_to_recover') AS _account,
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
    (SELECT av.id FROM hive.hafbe_app_accounts_view av WHERE av.name = _body->'value'->>'account') AS _account,
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

CREATE OR REPLACE FUNCTION hafbe_app.process_vote_op(op record, vote hive.account_witness_vote_operation)
RETURNS void
LANGUAGE 'plpgsql' VOLATILE
AS
$$
BEGIN
WITH vote_operation AS (
  SELECT
    (SELECT av.id FROM hive.hafbe_app_accounts_view av WHERE av.name = vote.account) AS voter_id,
    (SELECT av.id FROM hive.hafbe_app_accounts_view av WHERE av.name = vote.witness) AS witness_id,
    (vote.approve)::BOOLEAN AS approve,
    op.timestamp AS _time
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

CREATE OR REPLACE FUNCTION hafbe_app.process_proxy_op(op RECORD, proxy hive.account_witness_proxy_operation)
RETURNS void
LANGUAGE 'plpgsql' VOLATILE
AS
$$
BEGIN
WITH proxy_operations AS (
  SELECT
    proxy.account AS witness_account,
    proxy.proxy AS proxy_account,
    CASE WHEN op.op_type_id = 13 THEN TRUE ELSE FALSE END AS is_proxy,
    op.timestamp AS _time
),
selected AS (
    SELECT hav_a.id AS account_id, hav_p.id AS proxy_id, is_proxy, _time
    FROM proxy_operations proxy_op
    JOIN hive.hafbe_app_accounts_view hav_a ON hav_a.name = proxy_op.witness_account
    JOIN hive.hafbe_app_accounts_view hav_p ON hav_p.name = proxy_op.proxy_account
),
insert_proxy_history AS (
  INSERT INTO hafbe_app.account_proxies_history (account_id, proxy_id, proxy, timestamp)
  SELECT account_id, proxy_id, is_proxy, _time
  FROM selected
),
insert_current_proxies AS (
  INSERT INTO hafbe_app.current_account_proxies (account_id, proxy_id)
  SELECT account_id, proxy_id
  FROM selected
  WHERE is_proxy IS TRUE 
  ON CONFLICT ON CONSTRAINT pk_current_account_proxies DO UPDATE SET
    proxy_id = EXCLUDED.proxy_id
),
delete_votes_if_proxy AS (
  DELETE FROM hafbe_app.current_witness_votes cap USING (
    SELECT account_id 
    FROM selected
    WHERE is_proxy IS TRUE
  ) spo
  WHERE cap.voter_id = spo.account_id
)
DELETE FROM hafbe_app.current_account_proxies cap USING (
  SELECT account_id, proxy_id
  FROM selected
  WHERE is_proxy IS FALSE
) spo
WHERE cap.account_id = spo.account_id AND cap.proxy_id = spo.proxy_id
;

END
$$
;

CREATE OR REPLACE FUNCTION hafbe_app.process_proxy_op(op RECORD, proxy hive.proxy_cleared_operation)
RETURNS VOID
LANGUAGE 'plpgsql' VOLATILE
AS
$$
BEGIN
WITH proxy_operations AS (
  SELECT
    proxy.account AS witness_account,
    proxy.proxy AS proxy_account,
    CASE WHEN op.op_type_id = 13 THEN TRUE ELSE FALSE END AS is_proxy,
    op.timestamp AS _time
),
selected AS (
    SELECT av_a.id AS account_id, av_p.id AS proxy_id, is_proxy, _time
    FROM proxy_operations proxy_op
    JOIN hive.hafbe_app_accounts_view av_a ON av_a.name = proxy_op.witness_account
    JOIN hive.hafbe_app_accounts_view av_p ON av_p.name = proxy_op.proxy_account
),
insert_proxy_history AS (
  INSERT INTO hafbe_app.account_proxies_history (account_id, proxy_id, proxy, timestamp)
  SELECT account_id, proxy_id, is_proxy, _time
  FROM selected
),
insert_current_proxies AS (
  INSERT INTO hafbe_app.current_account_proxies (account_id, proxy_id)
  SELECT account_id, proxy_id
  FROM selected
  WHERE is_proxy IS TRUE 
  ON CONFLICT ON CONSTRAINT pk_current_account_proxies DO UPDATE SET
    proxy_id = EXCLUDED.proxy_id
),
delete_votes_if_proxy AS (
  DELETE FROM hafbe_app.current_witness_votes cap USING (
    SELECT account_id 
    FROM selected
    WHERE is_proxy IS TRUE
  ) spo
  WHERE cap.voter_id = spo.account_id
)
DELETE FROM hafbe_app.current_account_proxies cap USING (
  SELECT account_id, proxy_id
  FROM selected
  WHERE is_proxy IS FALSE
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
    (SELECT av.id FROM hive.hafbe_app_accounts_view av WHERE av.name = _body->'value'->>'account') AS account_id
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
