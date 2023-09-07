SET ROLE hafbe_owner;

CREATE OR REPLACE FUNCTION hafbe_app.process_create_account_operation(_body jsonb, _timestamp timestamp, _op_type int)
RETURNS void
LANGUAGE 'plpgsql' VOLATILE
AS
$$
BEGIN
WITH create_account_operation AS (
  SELECT
    (SELECT id FROM hive.hafbe_app_accounts_view WHERE name = _body->'value'->>'new_account_name') AS _account,
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
    (SELECT id FROM hive.hafbe_app_accounts_view WHERE name = _body->'value'->>'worker_account')
    ELSE
    (SELECT id FROM hive.hafbe_app_accounts_view WHERE name = _body->'value'->'work'->'value'->'input'->>'worker_account')
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
    (SELECT id FROM hive.hafbe_app_accounts_view WHERE name = _body->'value'->>'account') AS _account,
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
    (SELECT id FROM hive.hafbe_app_accounts_view WHERE name = _body->'value'->>'account_to_recover') AS _account,
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
    (SELECT id FROM hive.hafbe_app_accounts_view WHERE name = _body->'value'->>'account') AS _account,
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
    (SELECT id FROM hive.hafbe_app_accounts_view WHERE name = vote.account) AS voter_id,
    (SELECT id FROM hive.hafbe_app_accounts_view WHERE name = vote.witness) AS witness_id,
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
    TRUE AS is_proxy,
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
  ON CONFLICT ON CONSTRAINT pk_current_account_proxies DO UPDATE SET
    proxy_id = EXCLUDED.proxy_id
)
DELETE FROM hafbe_app.current_witness_votes cap USING (
  SELECT account_id 
  FROM selected
) spo
WHERE cap.voter_id = spo.account_id
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
    FALSE AS is_proxy,
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
)
DELETE FROM hafbe_app.current_account_proxies cap USING (
  SELECT account_id, proxy_id
  FROM selected
) spo
WHERE cap.account_id = spo.account_id AND cap.proxy_id = spo.proxy_id
;

END
$$;

CREATE OR REPLACE FUNCTION hafbe_app.process_expired_account(op RECORD, notification hive.expired_account_notification_operation)
RETURNS void
LANGUAGE 'plpgsql' VOLATILE
AS
$$
BEGIN
WITH proxy_operations AS (
  SELECT
    (SELECT id FROM hive.hafbe_app_accounts_view WHERE name = notification.account) AS account_id
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
$$
;

CREATE OR REPLACE FUNCTION hafbe_app.process_expired_account(op RECORD, decline hive.declined_voting_rights_operation)
RETURNS VOID
LANGUAGE 'plpgsql' VOLATILE
AS
$$
BEGIN
WITH proxy_operations AS (
  SELECT
    (SELECT id FROM hive.hafbe_app_accounts_view WHERE name = decline.account) AS account_id
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

DROP FUNCTION IF EXISTS hafbe_app.add_new_witness(op RECORD, vote hive.account_witness_vote_operation);
CREATE OR REPLACE FUNCTION hafbe_app.add_new_witness(op RECORD, vote hive.account_witness_vote_operation)
RETURNS VOID
AS
$function$
BEGIN
  INSERT INTO hafbe_app.current_witnesses (witness_id, url, price_feed, bias, feed_updated_at, block_size, signing_key, version)
  SELECT hav.id, NULL, NULL, NULL, NULL, NULL, NULL, NULL
  FROM hive.hafbe_app_accounts_view hav
  WHERE hav.name = vote.witness
  ON CONFLICT ON CONSTRAINT pk_current_witnesses DO NOTHING;
END
$function$
LANGUAGE 'plpgsql' VOLATILE;

DROP FUNCTION IF EXISTS hafbe_app.add_new_witness(op RECORD, props hive.witness_set_properties_operation);
CREATE OR REPLACE FUNCTION hafbe_app.add_new_witness(op RECORD, props hive.witness_set_properties_operation)
RETURNS VOID
AS
$function$
BEGIN
  INSERT INTO hafbe_app.current_witnesses (witness_id, url, price_feed, bias, feed_updated_at, block_size, signing_key, version)
  SELECT hav.id, NULL, NULL, NULL, NULL, NULL, NULL, NULL
  FROM hive.hafbe_app_accounts_view hav
  WHERE hav.name = (SELECT hive.get_impacted_accounts(op.body_binary))
  ON CONFLICT ON CONSTRAINT pk_current_witnesses DO NOTHING;
END
$function$
LANGUAGE 'plpgsql' VOLATILE;

DROP FUNCTION IF EXISTS hafbe_app.add_new_witness(op RECORD, upd hive.witness_update_operation);
CREATE OR REPLACE FUNCTION hafbe_app.add_new_witness(op RECORD, upd hive.witness_update_operation)
RETURNS VOID
AS
$function$
BEGIN
  INSERT INTO hafbe_app.current_witnesses (witness_id, url, price_feed, bias, feed_updated_at, block_size, signing_key, version)
  SELECT hav.id, NULL, NULL, NULL, NULL, NULL, NULL, NULL
  FROM hive.hafbe_app_accounts_view hav
  WHERE hav.name = (SELECT hive.get_impacted_accounts(op.body_binary))
  ON CONFLICT ON CONSTRAINT pk_current_witnesses DO NOTHING;
END
$function$
LANGUAGE 'plpgsql' VOLATILE;

DROP FUNCTION IF EXISTS hafbe_app.add_new_witness(op RECORD, feed hive.feed_publish_operation);
CREATE OR REPLACE FUNCTION hafbe_app.add_new_witness(op RECORD, feed hive.feed_publish_operation)
RETURNS VOID
AS
$function$
BEGIN
  INSERT INTO hafbe_app.current_witnesses (witness_id, url, price_feed, bias, feed_updated_at, block_size, signing_key, version)
  SELECT hav.id, NULL, NULL, NULL, NULL, NULL, NULL, NULL
  FROM hive.hafbe_app_accounts_view hav
  WHERE hav.name = (SELECT hive.get_impacted_accounts(op.body_binary))
  ON CONFLICT ON CONSTRAINT pk_current_witnesses DO NOTHING;
END
$function$
LANGUAGE 'plpgsql' VOLATILE;

DROP FUNCTION IF EXISTS hafbe_app.parse_witness_url(op RECORD, props hive.witness_set_properties_operation);
CREATE OR REPLACE FUNCTION hafbe_app.parse_witness_url(op RECORD, props hive.witness_set_properties_operation)
RETURNS VOID
AS
$function$
BEGIN
  UPDATE hafbe_app.current_witnesses cw SET url = ops.url FROM (
    SELECT hav.id AS witness_id, url
    FROM (
      SELECT
        trim(both '"' FROM prop_value::TEXT) AS url, op.witness
      FROM hive.extract_set_witness_properties(op.props)
      WHERE prop_name = 'url' AND url IS NOT NULL
    ) p
    JOIN hive.accounts_view hav ON hav.name = p.witness
  ) ops
  WHERE cw.witness_id = ops.witness_id;
END
$function$
LANGUAGE 'plpgsql' VOLATILE;

DROP FUNCTION IF EXISTS hafbe_app.parse_witness_url(op RECORD, upd hive.witness_update_operation);
CREATE OR REPLACE FUNCTION hafbe_app.parse_witness_url(op RECORD, upd hive.witness_update_operation)
RETURNS VOID
AS
$function$
BEGIN
  UPDATE hafbe_app.current_witnesses cw SET url = ops.url FROM (
    SELECT hav.id AS witness_id, upd.url
    FROM hive.accounts_view AS hav
    WHERE hav.name = op.witness AND upd.url IS NOT NULL
  ) ops
  WHERE cw.witness_id = ops.witness_id;
END
$function$
LANGUAGE 'plpgsql' VOLATILE;

DROP FUNCTION IF EXISTS hafbe_app.parse_witness_exchange_rate(op RECORD, props hive.witness_set_properties_operation);
CREATE OR REPLACE FUNCTION hafbe_app.parse_witness_exchange_rate(op RECORD, props hive.witness_set_properties_operation)
RETURNS VOID
AS
$function$
BEGIN
  UPDATE hafbe_app.current_witnesses cw SET
    price_feed = ops.price_feed,
    bias = ops.bias,
    feed_updated_at = ops.feed_updated_at
  FROM (
    SELECT
      hav.id AS witness_id,
      base / quote AS price_feed,
      (quote - 1000)::NUMERIC AS bias,
      props.timestamp AS feed_updated_at
    FROM (
      SELECT
        (exchange_rate->'base'->>'amount')::NUMERIC AS base,
        (exchange_rate->'quote'->>'amount')::NUMERIC AS quote
      FROM (
        SELECT trim(both '"' FROM prop_value::TEXT)::JSON AS exchange_rate
        FROM hive.extract_set_witness_properties(props.props)
        WHERE prop_name = 'hbd_exchange_rate' AND exchange_rate IS NOT NULL
      ) sp
    ) p
    JOIN hive.accounts_view hav ON hav.name = props.witness
  ) ops
  WHERE cw.witness_id = ops.witness_id;
END
$function$
LANGUAGE 'plpgsql' VOLATILE;

DROP FUNCTION IF EXISTS hafbe_app.parse_witness_exchange_rate(op RECORD, feed hive.feed_publish_operation);
CREATE OR REPLACE FUNCTION hafbe_app.parse_witness_exchange_rate(op RECORD, feed hive.feed_publish_operation)
RETURNS VOID
AS
$function$
BEGIN
  UPDATE hafbe_app.current_witnesses cw SET
    price_feed = ops.price_feed,
    bias = ops.bias,
    feed_updated_at = ops.feed_updated_at
  FROM (
    SELECT
      hav.id AS witness_id,
      base / quote AS price_feed,
      (quote - 1000)::NUMERIC AS bias,
      op.timestamp AS feed_updated_at
    FROM (
      SELECT
        (feed).exchange_rate.base.amount::NUMERIC AS base,
        (feed).exchange_rate.quote.amount::NUMERIC AS quote
      WHERE (feed).exchange_rate IS NOT NULL
    ) p
    JOIN hive.accounts_view hav ON hav.name = op.witness
  ) ops
  WHERE cw.witness_id = ops.witness_id;
END
$function$
LANGUAGE 'plpgsql' VOLATILE;

DROP FUNCTION IF EXISTS hafbe_app.parse_witness_block_size(op RECORD, props hive.witness_set_properties_operation);
CREATE OR REPLACE FUNCTION hafbe_app.parse_witness_block_size(op RECORD, props hive.witness_set_properties_operation)
RETURNS VOID
AS
$function$
BEGIN
  UPDATE hafbe_app.current_witnesses cw SET block_size = ops.block_size FROM (
    SELECT hav.id AS witness_id, block_size
    FROM (
      SELECT
        block_size::INT
      FROM (
        SELECT trim(both '"' FROM prop_value::TEXT) AS block_size
        FROM hive.extract_set_witness_properties(props.props)
        WHERE prop_name = 'maximum_block_size'
      ) sp
      WHERE block_size IS NOT NULL
    ) p
    JOIN hive.accounts_view hav ON hav.name = op.witness
  ) ops
  WHERE cw.witness_id = ops.witness_id;
END
$function$
LANGUAGE 'plpgsql' VOLATILE;

DROP FUNCTION IF EXISTS hafbe_app.parse_witness_block_size(op RECORD, upd hive.witness_update_operation);
CREATE OR REPLACE FUNCTION hafbe_app.parse_witness_block_size(op RECORD, upd hive.witness_update_operation)
RETURNS VOID
AS
$function$
BEGIN
  UPDATE hafbe_app.current_witnesses cw
  SET block_size = o.block_size
  FROM (
    SELECT hav.id AS witness_id, (upd).props.maximum_block_size AS block_size
    FROM hive.accounts_view AS hav
    WHERE hav.name = op.witness AND (upd).props.maximum_block_size IS NOT NULL
  ) o
  WHERE cw.witness_id = o.witness_id;
END
$function$
LANGUAGE 'plpgsql' VOLATILE;

DROP FUNCTION IF EXISTS hafbe_app.parse_witness_block_size(op RECORD, pow hive.pow_operation);
CREATE OR REPLACE FUNCTION hafbe_app.parse_witness_block_size(op RECORD, pow hive.pow_operation)
RETURNS VOID
AS
$function$
BEGIN
  UPDATE hafbe_app.current_witnesses cw
  SET block_size = o.block_size
  FROM (
    SELECT hav.id AS witness_id, (pow).props.maximum_block_size AS block_size
    FROM hive.accounts_view AS hav
    WHERE hav.name = op.witness AND (pow).props.maximum_block_size IS NOT NULL
  ) o
  WHERE cw.witness_id = o.witness_id;
END
$function$
LANGUAGE 'plpgsql' VOLATILE;

DROP FUNCTION IF EXISTS hafbe_app.parse_witness_block_size(op RECORD, pow hive.pow2_operation);
CREATE OR REPLACE FUNCTION hafbe_app.parse_witness_block_size(op RECORD, pow hive.pow2_operation)
RETURNS VOID
AS
$function$
BEGIN
  UPDATE hafbe_app.current_witnesses cw
  SET block_size = o.block_size
  FROM (
    SELECT hav.id AS witness_id, (pow).props.maximum_block_size AS block_size
    FROM hive.accounts_view AS hav
    WHERE hav.name = op.witness AND (pow).props.maximum_block_size IS NOT NULL
  ) o
  WHERE cw.witness_id = o.witness_id;
END
$function$
LANGUAGE 'plpgsql' VOLATILE;

DROP FUNCTION IF EXISTS hafbe_app.parse_witness_signing_key(op RECORD, props hive.witness_set_properties_operation);
CREATE OR REPLACE FUNCTION hafbe_app.parse_witness_signing_key(op RECORD, props hive.witness_set_properties_operation)
RETURNS VOID
AS
$function$
BEGIN
  UPDATE hafbe_app.current_witnesses cw SET signing_key = ops.signing_key FROM (
    SELECT hav.id AS witness_id, signing_key
    FROM (
      SELECT
        signing_key, op.witness
      FROM (
        SELECT COALESCE(
          (SELECT trim(both '"' FROM prop_value::TEXT)
            FROM hive.extract_set_witness_properties(props.props)
            WHERE prop_name = 'new_signing_key'),
          (SELECT trim(both '"' FROM prop_value::TEXT) AS signing_key
            FROM hive.extract_set_witness_properties(props.props)
            WHERE prop_name = 'key')) AS signing_key
      ) sp
      WHERE signing_key IS NOT NULL
    ) p
    JOIN hive.accounts_view hav ON hav.name = op.witness
  ) o
  WHERE cw.witness_id = o.witness_id;
END
$function$
LANGUAGE 'plpgsql' VOLATILE;

DROP FUNCTION IF EXISTS hafbe_app.parse_witness_signing_key(op RECORD, upd hive.witness_update_operation);
CREATE OR REPLACE FUNCTION hafbe_app.parse_witness_signing_key(op RECORD, upd hive.witness_update_operation)
RETURNS VOID
AS
$function$
BEGIN
  UPDATE hafbe_app.current_witnesses cw
  SET signing_key = o.signing_key
  FROM (
    SELECT hav.id AS witness_id, signing_key
    FROM (
      SELECT
        signing_key
      FROM (
        SELECT upd.block_signing_key AS signing_key
      ) sp
      WHERE signing_key IS NOT NULL
    ) prop
    JOIN hive.accounts_view hav ON hav.name = op.witness
  ) o
  WHERE cw.witness_id = o.witness_id;
END
$function$
LANGUAGE 'plpgsql' VOLATILE;

CREATE OR REPLACE FUNCTION hafbe_app.process_op_a(op RECORD, vote hive.account_witness_vote_operation)
RETURNS VOID
LANGUAGE 'plpgsql' VOLATILE
AS
$$
BEGIN
  PERFORM hafbe_app.process_vote_op(op, vote);
END
$$
;
CREATE OR REPLACE FUNCTION hafbe_app.process_op_a(op RECORD, proxy hive.account_witness_proxy_operation)
RETURNS VOID
LANGUAGE 'plpgsql' VOLATILE
AS
$$
BEGIN
  PERFORM hafbe_app.process_proxy_op(op, proxy);
END
$$
;
CREATE OR REPLACE FUNCTION hafbe_app.process_op_a(op RECORD, proxy hive.proxy_cleared_operation)
RETURNS VOID
LANGUAGE 'plpgsql' VOLATILE
AS
$$
BEGIN
  PERFORM hafbe_app.process_proxy_op(op, proxy);
END
$$
;
CREATE OR REPLACE FUNCTION hafbe_app.process_op_a(op RECORD, notification hive.expired_account_notification_operation)
RETURNS VOID
LANGUAGE 'plpgsql' VOLATILE
AS
$$
BEGIN
  PERFORM hafbe_app.process_expired_account(op, notification);
END
$$
;
CREATE OR REPLACE FUNCTION hafbe_app.process_op_a(op RECORD, decline hive.declined_voting_rights_operation)
RETURNS VOID
LANGUAGE 'plpgsql' VOLATILE
AS
$$
BEGIN
  PERFORM hafbe_app.process_expired_account(op, decline);
END
$$
;

RESET ROLE;
