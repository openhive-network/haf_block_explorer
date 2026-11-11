SET ROLE hafbe_owner;

-- Sets current_proposals.total_budget where block processing has not kept it:
-- on an install that db/add_proposal_total_budget.sql upgraded, every row that
-- existed before is NULL. No replay of blocks is needed. install_app.sh applies
-- this after the processing functions, so from here on STEP A and
-- process_proposal_update_op keep the column; a row the previous code created
-- while the column already existed is still NULL and is filled here.
--
-- Every updated proposal is also re-checked on each install, not only NULL
-- ones: an older hafbe installed over a database that already had the column
-- would apply updates to daily_pay and end_date without adjusting total_budget,
-- and the next upgrade must not keep serving that stale value. A row is written
-- only when its value changes. Never-updated rows cannot go stale that way (no
-- update to miss), so only their NULLs are filled.
--
-- Values are computed with the functions block processing uses
-- (proposal_term_pay, proposal_budget_after_update), so they match a fresh sync:
--   - a proposal no update_proposal_operation names: daily_pay x term, from the row;
--   - an updated proposal: its create (paired with its proposal_fee_operation
--     the way STEP A of process_proposals pairs them) and then its updates, in
--     operation order, each at its block time.
-- A replay that does not end on the row's daily_pay and end_date sets NULL with
-- a warning: the API returns a NULL total_budget as null, which clients treat
-- as unknown, while a wrong one would be shown as real.
--
-- Run without a block processor (production installs hold the app lock): each
-- statement takes its own snapshot, so a block committed in between could pair
-- an update with a stale row.
DO $$
DECLARE
  _op_create_proposal INT := (SELECT id FROM hafd.operation_types WHERE name = 'hive::protocol::create_proposal_operation');
  _op_proposal_fee    INT := (SELECT id FROM hafd.operation_types WHERE name = 'hive::protocol::proposal_fee_operation');
  _op_update_proposal INT := (SELECT id FROM hafd.operation_types WHERE name = 'hive::protocol::update_proposal_operation');
  __updated  INT[];
  __p        RECORD;
  __u        RECORD;
  __budget   NUMERIC;
  __pay      BIGINT;
  __end      TIMESTAMP;
  __new_pay  BIGINT;
  __new_end  TIMESTAMP;
  __filled   INT;
  __changed  INT := 0;
  __nulled   INT := 0;
BEGIN
  -- Every lookup below reads operations by type. HAF drops that index during
  -- massive sync, and without it each lookup scans all operations: skip, and
  -- leave NULLs to the next install after the sync (the API returns them as null).
  IF to_regclass('hafd.hive_operations_op_type_id_block_num') IS NULL THEN
    RAISE NOTICE 'total_budget backfill skipped: hafd.hive_operations_op_type_id_block_num does not exist (HAF massive sync?); % rows stay NULL until install_app.sh runs again',
      (SELECT COUNT(*) FROM hafbe_app.current_proposals WHERE total_budget IS NULL);
    RETURN;
  END IF;

  __updated := ARRAY(
    SELECT DISTINCT (ov.body_value ->> 'proposal_id')::INT
    FROM hafbe_app.operations_view ov
    WHERE ov.op_type_id = _op_update_proposal
  );

  -- Never updated: the created pay over the created term, all still in the row.
  UPDATE hafbe_app.current_proposals cp
  SET total_budget = ROUND(hafbe_backend.proposal_term_pay(cp.daily_pay, cp.start_date, cp.end_date))
  WHERE cp.total_budget IS NULL
    AND cp.proposal_id <> ALL (__updated);
  GET DIAGNOSTICS __filled = ROW_COUNT;

  -- Updated (every NULL left is one): replay. Ranks are computed over every create and fee in the blocks
  -- that hold the targets' fees, as STEP A does, so other proposals created by
  -- the same account in the same block keep the pairing right.
  FOR __p IN
    WITH target_blocks AS (
      SELECT DISTINCT ov.block_num
      FROM hafbe_app.operations_view ov
      WHERE ov.op_type_id = _op_proposal_fee
        AND (ov.body_value ->> 'proposal_id')::INT = ANY (__updated)
    ),
    create_ops AS (
      SELECT
        ov.block_num,
        ov.body_value ->> 'creator'                         AS creator_name,
        (ov.body_value -> 'daily_pay' ->> 'amount')::BIGINT AS daily_pay,
        (ov.body_value ->> 'end_date')::TIMESTAMP          AS end_date,
        ROW_NUMBER() OVER (
          PARTITION BY ov.block_num, ov.body_value ->> 'creator'
          ORDER BY ov.id
        ) AS rk
      FROM hafbe_app.operations_view ov
      WHERE ov.op_type_id = _op_create_proposal
        AND ov.block_num IN (SELECT tb.block_num FROM target_blocks tb)
    ),
    fee_ops AS (
      SELECT
        ov.block_num,
        ov.body_value ->> 'creator'             AS creator_name,
        (ov.body_value ->> 'proposal_id')::INT AS proposal_id,
        ROW_NUMBER() OVER (
          PARTITION BY ov.block_num, ov.body_value ->> 'creator'
          ORDER BY ov.id
        ) AS rk
      FROM hafbe_app.operations_view ov
      WHERE ov.op_type_id = _op_proposal_fee
        AND ov.block_num IN (SELECT tb.block_num FROM target_blocks tb)
    )
    SELECT
      cp.proposal_id,
      cp.start_date,
      cp.daily_pay AS row_pay,
      cp.end_date  AS row_end,
      c.daily_pay  AS created_pay,
      c.end_date   AS created_end
    FROM fee_ops f
    JOIN create_ops c
      ON c.block_num    = f.block_num
     AND c.creator_name = f.creator_name
     AND c.rk           = f.rk
    JOIN hafbe_app.current_proposals cp ON cp.proposal_id = f.proposal_id
    WHERE f.proposal_id = ANY (__updated)
  LOOP
    __pay    := __p.created_pay;
    __end    := __p.created_end;
    __budget := ROUND(hafbe_backend.proposal_term_pay(__pay, __p.start_date, __end));

    FOR __u IN
      -- Block time from blocks_view, as process_proposal_update_op reads it. A
      -- per-row lookup: joined, the reversible-union view is hashed in full.
      SELECT
        ov.body_value,
        (SELECT bv.created_at FROM hafbe_app.blocks_view bv WHERE bv.num = ov.block_num) AS created_at
      FROM hafbe_app.operations_view ov
      WHERE ov.op_type_id = _op_update_proposal
        AND (ov.body_value ->> 'proposal_id')::INT = __p.proposal_id
      ORDER BY ov.id
    LOOP
      __new_pay := (__u.body_value -> 'daily_pay' ->> 'amount')::BIGINT;
      __new_end := COALESCE(hafbe_backend.proposal_update_end_date(__u.body_value), __end);
      __budget  := hafbe_backend.proposal_budget_after_update(
                     __budget, __p.start_date, __pay, __end, __new_pay, __new_end, __u.created_at);
      __pay     := __new_pay;
      __end     := __new_end;
    END LOOP;

    IF __budget IS NULL OR __pay IS DISTINCT FROM __p.row_pay OR __end IS DISTINCT FROM __p.row_end THEN
      RAISE WARNING 'total_budget of proposal % set NULL: replay gave %, ending at pay % and end date %; the row has % and %',
        __p.proposal_id, __budget, __pay, __end, __p.row_pay, __p.row_end;
      UPDATE hafbe_app.current_proposals cp
      SET total_budget = NULL
      WHERE cp.proposal_id = __p.proposal_id
        AND cp.total_budget IS NOT NULL;
      __nulled := __nulled + 1;
      CONTINUE;
    END IF;

    UPDATE hafbe_app.current_proposals cp
    SET total_budget = __budget
    WHERE cp.proposal_id = __p.proposal_id
      AND cp.total_budget IS DISTINCT FROM __budget;
    IF FOUND THEN
      __changed := __changed + 1;
    END IF;
  END LOOP;

  RAISE NOTICE 'total_budget backfill: % filled from their row, % set or corrected by replay, % unverifiable (NULL); % NULL in all',
    __filled, __changed, __nulled,
    (SELECT COUNT(*) FROM hafbe_app.current_proposals WHERE total_budget IS NULL);
END
$$;

RESET ROLE;
