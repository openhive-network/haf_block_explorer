SET ROLE hafbe_owner;

CREATE OR REPLACE FUNCTION hafbe_backend.process_votes_and_proxies(IN _operation_body JSONB, IN _op_type_id INT, IN source_op BIGINT, IN source_op_block INT)
RETURNS void
LANGUAGE plpgsql
VOLATILE
AS
$$
BEGIN
  PERFORM (
    CASE 
      WHEN _op_type_id = 12 THEN
      hafbe_backend.process_vote_op(_operation_body, source_op, source_op_block)

      WHEN _op_type_id = 13 OR _op_type_id = 91 THEN
      hafbe_backend.process_proxy_ops(_operation_body, source_op, source_op_block, _op_type_id)

      WHEN _op_type_id = 92 OR _op_type_id = 75 THEN
      hafbe_backend.process_expired_accounts(_operation_body, source_op, source_op_block)
    END
  );

END;
$$;

CREATE OR REPLACE FUNCTION hafbe_backend.process_vote_op(_body jsonb, _id BIGINT, _block_num INT)
RETURNS void
LANGUAGE 'plpgsql' VOLATILE
AS
$$
DECLARE 
  _voter_id INT := (SELECT av.id FROM hafbe_app.accounts_view av WHERE av.name = _body->'value'->>'account');
  _witness_id INT := (SELECT av.id FROM hafbe_app.accounts_view av WHERE av.name = _body->'value'->>'witness');
  _approve BOOLEAN := (_body->'value'->>'approve')::BOOLEAN;
BEGIN
  -- Insert the vote into the history table
  INSERT INTO hafbe_app.witness_votes_history (witness_id, voter_id, approve, source_op, source_op_block)
  SELECT _witness_id, _voter_id, _approve, _id, _block_num;

  -- If the vote is approved, insert it into the current votes table
  INSERT INTO hafbe_app.current_witness_votes (witness_id, voter_id, source_op, source_op_block)
  SELECT _witness_id, _voter_id, _id, _block_num
  WHERE _approve
  ON CONFLICT ON CONSTRAINT pk_current_witness_votes DO UPDATE SET
    source_op_block = EXCLUDED.source_op_block,
    source_op = EXCLUDED.source_op;

  -- If the vote is not approved, delete it from the current votes table
  DELETE FROM hafbe_app.current_witness_votes cwv 
  WHERE cwv.witness_id = _witness_id AND cwv.voter_id = _voter_id AND NOT _approve;

END
$$;

CREATE OR REPLACE FUNCTION hafbe_backend.process_proxy_ops(_body jsonb, _id BIGINT, _block_num INT, _op_type int)
RETURNS void
LANGUAGE 'plpgsql' VOLATILE
AS
$$
DECLARE 
  _account_id INT := (SELECT av.id FROM hafbe_app.accounts_view av WHERE av.name = _body->'value'->>'account');
  _proxy_id INT := (SELECT av.id FROM hafbe_app.accounts_view av WHERE av.name = _body->'value'->>'proxy');
  _proxy BOOLEAN := (CASE WHEN _op_type = 13 THEN TRUE ELSE FALSE END);
BEGIN
  -- Insert the proxy operation into the history table
  INSERT INTO hafbe_app.account_proxies_history (account_id, proxy_id, proxy, source_op, source_op_block)
  SELECT _account_id, _proxy_id, _proxy, _id, _block_num
  WHERE _proxy_id IS NOT NULL;

  -- If the proxy is approved, insert it into the current proxy table
  INSERT INTO hafbe_app.current_account_proxies (account_id, proxy_id, source_op, source_op_block)
  SELECT _account_id, _proxy_id, _id, _block_num
  WHERE _proxy AND _proxy_id IS NOT NULL
  ON CONFLICT ON CONSTRAINT pk_current_account_proxies DO UPDATE SET
    proxy_id = EXCLUDED.proxy_id,
    source_op_block = EXCLUDED.source_op_block,
    source_op = EXCLUDED.source_op;

  -- If the proxy is removed, delete it from the current proxy table
  DELETE FROM hafbe_app.current_account_proxies cap 
  WHERE 
    cap.account_id = _account_id AND 
    cap.proxy_id = _proxy_id AND
    NOT _proxy AND _proxy_id IS NOT NULL;

  -- If the proxy is set, delete any existing witness votes for the account 
  WITH delete_votes_if_proxy AS (
    DELETE FROM hafbe_app.current_witness_votes cap 
    WHERE cap.voter_id = _account_id AND _proxy AND _proxy_id IS NOT NULL
    RETURNING cap.voter_id, cap.witness_id
  )
  -- and insert them into the history table 
  INSERT INTO hafbe_app.witness_votes_history (witness_id, voter_id, approve, source_op, source_op_block)
  SELECT cap.witness_id, cap.voter_id, FALSE, _id, _block_num
  FROM delete_votes_if_proxy cap;

END
$$;

CREATE OR REPLACE FUNCTION hafbe_backend.process_expired_accounts(_body jsonb, _id BIGINT, _block_num INT)
RETURNS void
LANGUAGE 'plpgsql' VOLATILE
AS
$$
DECLARE
  _account_id INT := (SELECT av.id FROM hafbe_app.accounts_view av WHERE av.name = _body->'value'->>'account');
BEGIN
  -- Delete the account from the current proxies table
  WITH delete_proxies AS (
    DELETE FROM hafbe_app.current_account_proxies cap
    WHERE cap.account_id = _account_id
    RETURNING cap.account_id, cap.proxy_id
  )
  -- and insert the deleted proxies into the history table
  INSERT INTO hafbe_app.account_proxies_history (account_id, proxy_id, proxy, source_op, source_op_block)
  SELECT cap.account_id, cap.proxy_id, FALSE, _id, _block_num
  FROM delete_proxies cap;

  -- Delete the account from the current votes table
  WITH delete_votes AS (
    DELETE FROM hafbe_app.current_witness_votes cap 
    WHERE cap.voter_id = _account_id
    RETURNING cap.voter_id, cap.witness_id
  )
  -- and insert the deleted votes into the history table
  INSERT INTO hafbe_app.witness_votes_history (witness_id, voter_id, approve, source_op, source_op_block)
  SELECT cap.witness_id, cap.voter_id, FALSE, _id, _block_num
  FROM delete_votes cap;

END
$$;

RESET ROLE;
