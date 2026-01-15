SET ROLE hafbe_owner;

CREATE OR REPLACE FUNCTION hafbe_app.process_account_stats(_from INT, _to INT)
RETURNS VOID
LANGUAGE 'plpgsql' VOLATILE
SET from_collapse_limit = 16
SET join_collapse_limit = 16
SET jit = OFF
AS
$$
DECLARE
  -- Operation type IDs for account parameters
  _op_pow                            INT := hafbe_backend.op_pow();
  _op_pow2                           INT := hafbe_backend.op_pow2();
  _op_account_created                INT := hafbe_backend.op_account_created();
  _op_account_create                 INT := hafbe_backend.op_account_create();
  _op_create_claimed_account         INT := hafbe_backend.op_create_claimed_account();
  _op_account_create_with_delegation INT := hafbe_backend.op_account_create_with_delegation();
  _op_changed_recovery_account       INT := hafbe_backend.op_changed_recovery_account();
  -- Operation type IDs for other account stats
  _op_recover_account                INT := hafbe_backend.op_recover_account();
  _op_decline_voting_rights          INT := hafbe_backend.op_decline_voting_rights();
  _op_claim_account                  INT := hafbe_backend.op_claim_account();
BEGIN
  -- parse account parameters: mined, recovery_account, created
  -- First CTE: fetch operations with needed data
  WITH ops_in_range AS MATERIALIZED (
    SELECT
      ho.body,
      ho.op_type_id,
      ho.id AS source_op,
      ho.block_num AS source_op_block,
      hb.created_at,
      ho.block_num > ah.block_num AS is_after_hf11
    FROM hafbe_app.operations_view ho
    JOIN hafd.applied_hardforks ah ON ah.hardfork_num = 11
    JOIN hive.blocks_view hb ON hb.num = ho.block_num
    WHERE
      ho.op_type_id IN (_op_pow, _op_pow2, _op_account_created, _op_account_create, _op_create_claimed_account, _op_account_create_with_delegation, _op_changed_recovery_account) AND
      ho.block_num BETWEEN _from AND _to
  ),
  -- Second CTE: parse JSON once using helper functions
  parsed_ops AS MATERIALIZED (
    SELECT
      iap.account_name,
      iap.mined,
      iap.recovery_account,
      iap.created,
      o.op_type_id,
      o.source_op,
      o.source_op_block
    FROM ops_in_range o
    CROSS JOIN LATERAL (
      SELECT (
        CASE
          WHEN o.op_type_id = _op_pow THEN
            hafbe_backend.process_pow_operation(o.body, o.created_at)
          WHEN o.op_type_id = _op_pow2 THEN
            hafbe_backend.process_pow_two_operation(o.body, o.created_at)
          WHEN o.op_type_id = _op_account_created THEN
            hafbe_backend.process_created_account_operation(o.body, o.created_at, o.is_after_hf11)
          WHEN o.op_type_id IN (_op_account_create, _op_create_claimed_account, _op_account_create_with_delegation) THEN
            hafbe_backend.process_create_account_operation(o.body, o.created_at)
          WHEN o.op_type_id = _op_changed_recovery_account THEN
            hafbe_backend.process_changed_recovery_account_operation(o.body)
        END
      ).*
    ) AS iap
  ),
  add_row_num AS MATERIALIZED (
    SELECT
      (SELECT av.id FROM hafbe_app.accounts_view av WHERE av.name = account_name) AS account_id,
      mined,
      recovery_account,
      created,
      op_type_id,
      source_op,
      source_op_block,
      ROW_NUMBER() OVER (PARTITION BY account_name ORDER BY source_op) AS row_num_asc,
      ROW_NUMBER() OVER (PARTITION BY account_name ORDER BY source_op DESC) AS row_num_desc
    FROM parsed_ops
  ),
  get_latest_parameters AS (
    SELECT
      ar.account_id,
      ap.mined,
      ap.recovery_account,
      ap.created,
      0 AS op_type_id,
      0 AS source_op,
      0 AS source_op_block,
      0 AS row_num_asc,
      0 AS row_num_desc
    FROM add_row_num ar
    LEFT JOIN hafbe_app.account_parameters ap ON ap.account = ar.account_id
    WHERE ar.row_num_asc = 1
  ),
  union_records AS MATERIALIZED (
    SELECT
      account_id,
      mined,
      recovery_account,
      created,
      op_type_id,
      source_op,
      source_op_block,
      row_num_asc,
      row_num_desc
    FROM get_latest_parameters

    UNION ALL

    SELECT
      account_id,
      mined,
      recovery_account,
      created,
      op_type_id,
      source_op,
      source_op_block,
      row_num_asc,
      row_num_desc
    FROM add_row_num
  ),
  recursive_params AS (
    WITH RECURSIVE account_parameters AS (
      SELECT
        ed.account_id,
        ed.mined,
        ed.recovery_account,
        ed.created,
        ed.op_type_id,
        ed.source_op,
        ed.source_op_block,
        ed.row_num_asc,
        ed.row_num_desc
      FROM union_records ed
      WHERE ed.row_num_asc = 0

      UNION ALL

      SELECT
        prev.account_id,
        (
          CASE
            WHEN prev.mined IS NOT NULL THEN
              prev.mined
            ELSE
              next_cp.mined
          END
        ) AS mined,
        (
          CASE
            WHEN next_cp.recovery_account IS NOT NULL THEN
              next_cp.recovery_account
            ELSE
              prev.recovery_account
          END
        ) AS recovery_account,
        (
          CASE
            WHEN next_cp.op_type_id = _op_account_created THEN
              next_cp.created
            WHEN next_cp.op_type_id != _op_account_created AND prev.created IS NOT NULL THEN
              prev.created
            ELSE
              next_cp.created
          END
        ) AS created,
        next_cp.op_type_id,
        next_cp.source_op,
        next_cp.source_op_block,
        next_cp.row_num_asc,
        next_cp.row_num_desc
      FROM account_parameters prev
      JOIN union_records next_cp ON
        next_cp.account_id  = prev.account_id AND
        next_cp.row_num_asc = prev.row_num_asc + 1
    )
    SELECT * FROM account_parameters
    WHERE row_num_desc = 1
  )
  INSERT INTO hafbe_app.account_parameters AS rt
    (account, mined, recovery_account, created)
  SELECT
    rp.account_id,
    COALESCE(rp.mined, TRUE::BOOLEAN),
    COALESCE(rp.recovery_account, ''::TEXT),
    COALESCE(rp.created, '1970-01-01T00:00:00'::TIMESTAMP)
  FROM recursive_params rp
  ON CONFLICT ON CONSTRAINT pk_account_parameters
  DO UPDATE SET
      mined = EXCLUDED.mined,
      recovery_account = EXCLUDED.recovery_account,
      created = EXCLUDED.created;

  -- parse account parameters: last_account_recovery
  WITH select_ops_with_last_account_recovery AS MATERIALIZED (
    SELECT
      ov.body->'value'->>'account_to_recover' AS account_name,
      ov.block_num AS source_op_block,
      ov.id AS source_op
    FROM hafbe_app.operations_view ov
    WHERE ov.op_type_id = _op_recover_account AND ov.block_num BETWEEN _from AND _to
  ),
  add_row_num AS (
    SELECT
      so.account_name,
      so.source_op_block,
      so.source_op,
      ROW_NUMBER() OVER (PARTITION BY so.account_name ORDER BY so.source_op DESC) AS row_num_desc
    FROM select_ops_with_last_account_recovery so
  )
  INSERT INTO hafbe_app.account_parameters AS ap
    (account, last_account_recovery)
  SELECT
    (SELECT av.id FROM hafbe_app.accounts_view av WHERE av.name = ar.account_name),
    bv.created_at
  FROM add_row_num ar
  JOIN hive.blocks_view bv ON bv.num = ar.source_op_block
  WHERE ar.row_num_desc = 1
  ON CONFLICT ON CONSTRAINT pk_account_parameters DO
  UPDATE SET
    last_account_recovery = EXCLUDED.last_account_recovery;

  -- parse account parameters: can_vote
  WITH select_ops_with_can_vote AS MATERIALIZED (
    SELECT
      ov.body->'value'->>'account' AS account_name,
      CASE WHEN (ov.body->'value'->>'decline')::BOOLEAN = TRUE THEN FALSE ELSE TRUE END AS can_vote,
      ov.block_num AS source_op_block,
      ov.id AS source_op
    FROM hafbe_app.operations_view ov
    WHERE ov.op_type_id = _op_decline_voting_rights AND ov.block_num BETWEEN _from AND _to
  ),
  add_row_num AS (
    SELECT
      so.account_name,
      so.can_vote,
      so.source_op_block,
      so.source_op,
      ROW_NUMBER() OVER (PARTITION BY so.account_name ORDER BY so.source_op DESC) AS row_num_desc
    FROM select_ops_with_can_vote so
  )
  INSERT INTO hafbe_app.account_parameters AS ap
    (account, can_vote)
  SELECT
    (SELECT av.id FROM hafbe_app.accounts_view av WHERE av.name = ar.account_name),
    ar.can_vote
  FROM add_row_num ar
  WHERE ar.row_num_desc = 1
  ON CONFLICT ON CONSTRAINT pk_account_parameters DO
  UPDATE SET
    can_vote = EXCLUDED.can_vote;

  -- parse account parameters: pending_claimed_accounts
  WITH select_ops_with_claimed AS MATERIALIZED (
    SELECT
      (body -> 'value' ->> 'creator') AS account,
      (
        CASE WHEN ov.op_type_id = _op_claim_account THEN
          1
        ELSE
          -1
        END
      ) AS claimed_account
    FROM hafbe_app.operations_view ov
    WHERE ov.op_type_id IN (_op_claim_account, _op_create_claimed_account) AND ov.block_num BETWEEN _from AND _to
  ),
  count_claimed AS (
    SELECT
      so.account,
      SUM(so.claimed_account) AS claimed_account
    FROM select_ops_with_claimed so
    GROUP BY so.account
  )
  INSERT INTO hafbe_app.account_parameters AS ap
    (account, pending_claimed_accounts)
  SELECT
    (SELECT av.id FROM hafbe_app.accounts_view av WHERE av.name = cm.account),
    cm.claimed_account
  FROM count_claimed cm
  ON CONFLICT ON CONSTRAINT pk_account_parameters DO
  UPDATE SET
    pending_claimed_accounts = ap.pending_claimed_accounts + EXCLUDED.pending_claimed_accounts;

END
$$;

RESET ROLE;
