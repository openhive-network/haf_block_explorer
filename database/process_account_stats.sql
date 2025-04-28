SET ROLE hafbe_owner;

CREATE OR REPLACE FUNCTION hafbe_app.process_account_stats(_from INT, _to INT)
RETURNS VOID
LANGUAGE 'plpgsql' VOLATILE
SET from_collapse_limit = 16
SET join_collapse_limit = 16
SET jit = OFF
AS
$$
BEGIN
  -- parse account parameters: mined, recovery_account, created
  WITH ops_in_range AS (
    SELECT 
      iap.account_name,
      iap.mined,
      iap.recovery_account,
      iap.created,
      ho.op_type_id,
      ho.id AS source_op,
      ho.block_num AS source_op_block
    FROM hafbe_app.operations_view ho --- APP specific view must be used, to correctly handle reversible part of the data.
    JOIN hafd.applied_hardforks ah ON ah.hardfork_num = 11
    JOIN hive.blocks_view hb ON hb.num = ho.block_num
    CROSS JOIN hafbe_backend.get_impacted_account_parameters(
      ho.body, 
      ho.op_type_id,
      hb.created_at,
      ho.block_num > ah.block_num
    ) AS iap
    WHERE 
      ho.op_type_id IN (14, 30, 80, 9, 23, 41, 76) AND 
      ho.block_num BETWEEN _from AND _to
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
    FROM ops_in_range
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
            WHEN next_cp.op_type_id = 80 THEN
              next_cp.created
            WHEN next_cp.op_type_id != 80 AND prev.created IS NOT NULL THEN
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
  WITH select_ops_with_last_account_recovery AS (
    SELECT 
      hafbe_backend.process_recover_account_operation(ov.body) AS account_name,
      ov.block_num AS source_op_block,
      ov.id AS source_op
    FROM hafbe_app.operations_view ov
    WHERE ov.op_type_id = 25 AND ov.block_num BETWEEN _from AND _to
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
  WITH select_ops_with_can_vote AS (
    SELECT 
      cv.account_name,
      cv.can_vote,
      ov.block_num AS source_op_block,
      ov.id AS source_op
    FROM hafbe_app.operations_view ov
    CROSS JOIN hafbe_backend.process_decline_voting_rights_operation(ov.body) AS cv
    WHERE ov.op_type_id = 36 AND ov.block_num BETWEEN _from AND _to
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
  WITH select_ops_with_claimed AS (
    SELECT 
      (body -> 'value' ->> 'creator') AS account,
      (
        CASE WHEN ov.op_type_id = 22 THEN
          1
        ELSE
          -1
        END
      ) AS claimed_account
    FROM hafbe_app.operations_view ov
    WHERE ov.op_type_id IN (22,23) AND ov.block_num BETWEEN _from AND _to
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
