SET ROLE hafbe_owner;

CREATE OR REPLACE FUNCTION hafbe_backend.process_votes_and_proxies(IN _operation_body JSONB, IN _op_type_id INT, _timestamp TIMESTAMP)
RETURNS void
LANGUAGE plpgsql
VOLATILE
AS
$$
BEGIN
  PERFORM (
    CASE 
      WHEN _op_type_id = 12 THEN
      hafbe_backend.process_vote_op(_operation_body, _timestamp)

      WHEN _op_type_id = 13 OR _op_type_id = 91 THEN
      hafbe_backend.process_proxy_ops(_operation_body, _timestamp, _op_type_id)

      WHEN _op_type_id = 92 OR _op_type_id = 75 THEN
      hafbe_backend.process_expired_accounts(_operation_body)
    END
  );

END;
$$;

CREATE OR REPLACE FUNCTION hafbe_backend.process_vote_op(_body jsonb, _timestamp timestamp)
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

CREATE OR REPLACE FUNCTION hafbe_backend.process_proxy_ops(_body jsonb, _timestamp timestamp, _op_type int)
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

CREATE OR REPLACE FUNCTION hafbe_backend.process_expired_accounts(_body jsonb)
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
