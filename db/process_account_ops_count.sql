SET ROLE hafbe_owner;

/*
 * account_ops_counts_until: Each account's operation count as of an irreversible
 * block.
 *
 * The count is the newest account_op_seq_no + 1 at or below _last_block, one
 * backward probe of hafd.account_operations' (account_id, account_op_seq_no) index
 * per account. Reads the irreversible table directly: through the context's
 * account_operations_view the planner sorts every row of each account instead.
 * Accounts without operations are left out.
 *
 * PARAMETERS:
 *   _last_block - Last block whose operations are counted; must be irreversible
 */
CREATE OR REPLACE FUNCTION hafbe_app.account_ops_counts_until(_last_block INT)
RETURNS TABLE (account_id INT, ops_count INT)
LANGUAGE 'plpgsql' STABLE
AS
$$
BEGIN
  RETURN QUERY
  SELECT
    av.id,
    newest.account_op_seq_no + 1
  FROM hafbe_app.accounts_view av
  CROSS JOIN LATERAL (
    SELECT ao.account_op_seq_no
    FROM hafd.account_operations ao
    WHERE ao.account_id = av.id
      AND ao.operation_id < hafd.operation_id(_last_block + 1, 0)
    ORDER BY ao.account_op_seq_no DESC
    LIMIT 1
  ) newest;
END
$$;

/*
 * finalize_account_ops_count: Sets hafbe_app.account_ops_count to the counts as
 * of _last_block, while the context is not yet forking.
 *
 * process_account_ops_count() maintains the table only once the context is
 * forking: during the initial massive sync this one pass per account replaces
 * decoding every operation of the chain. It runs before the switch to forking so
 * that HAF's rewind triggers do not copy a row per account into the shadow table
 * (haf#346). A no-op once the context is forking.
 *
 * The only block-processing step that reads hafd.account_operations. When the
 * massive sync started while hived replayed (early block processing), hived
 * restores that table's indexes only when the replay ends, and rebuilds the table
 * with CLUSTER under an ACCESS EXCLUSIVE lock: this waits until it is done, which
 * takes about 2.5 hours on mainnet. Raises when the wait times out.
 *
 * PARAMETERS:
 *   _last_block - Last block the context has processed (irreversible, as every
 *                 block a non-forking context processes)
 */
CREATE OR REPLACE FUNCTION hafbe_app.finalize_account_ops_count(_last_block INT)
RETURNS VOID
LANGUAGE 'plpgsql' VOLATILE
AS
$$
BEGIN
  IF hive.app_is_forking('hafbe_app') THEN
    RETURN;
  END IF;

  -- A HAF older than haf#379 delivers blocks only once every core index exists.
  IF to_regprocedure('hive.wait_for_core_indexes(hive.contexts_group, text, text, interval, interval)') IS NOT NULL THEN
    PERFORM hive.wait_for_core_indexes(
      (SELECT a.contexts FROM hafd.applications a WHERE a.name = 'hafbe_app')::hive.contexts_group,
      'hafd.account_operations', NULL, '6 hours'
    );
  END IF;

  INSERT INTO hafbe_app.account_ops_count AS aoc (account_id, ops_count)
  SELECT c.account_id, c.ops_count
  FROM hafbe_app.account_ops_counts_until(_last_block) c
  ON CONFLICT ON CONSTRAINT pk_account_ops_count DO UPDATE SET
    ops_count = EXCLUDED.ops_count;
END
$$;

/*
 * process_account_ops_count: Adds the block range's operations to each impacted
 * account's count in hafbe_app.account_ops_count.
 *
 * HAF writes one hafd.account_operations row per (operation, account in
 * hive.get_impacted_accounts()), so an account's count grows by the number of
 * the range's operations that impact it. hafd.account_operations itself has no
 * index by block, so the range is read from the operations instead.
 *
 * Does nothing while the context is not forking (initial massive sync):
 * finalize_account_ops_count() fills the table before the switch to forking.
 */
CREATE OR REPLACE FUNCTION hafbe_app.process_account_ops_count(_from INT, _to INT)
RETURNS VOID
LANGUAGE 'plpgsql' VOLATILE
AS
$$
BEGIN
  IF NOT hive.app_is_forking('hafbe_app') THEN
    RETURN;
  END IF;

  WITH impacted AS (
    SELECT
      ia.name,
      COUNT(*)::INT AS ops
    FROM hafbe_app.operations_view ov
    CROSS JOIN hive.get_impacted_accounts(ov.body::hafd.operation) AS ia (name)
    WHERE ov.block_num BETWEEN _from AND _to
      AND ov.id >= hafd.operation_id(_from, 0)
      AND ov.id < hafd.operation_id(_to + 1, 0)
    GROUP BY ia.name
  ),

  -- One name lookup per account: the planner, which cannot estimate the
  -- function scan, otherwise joins by hashing every account.
  resolved AS (
    SELECT
      (SELECT av.id FROM hafbe_app.accounts_view av WHERE av.name = i.name) AS account_id,
      i.ops
    FROM impacted i
  )
  INSERT INTO hafbe_app.account_ops_count AS aoc (account_id, ops_count)
  SELECT r.account_id, r.ops
  FROM resolved r
  WHERE r.account_id IS NOT NULL
  ON CONFLICT ON CONSTRAINT pk_account_ops_count DO UPDATE SET
    ops_count = aoc.ops_count + EXCLUDED.ops_count;
END
$$;

/*
 * account_ops_count: Number of operations of each account
 * -------------------------------------------------------
 * One row per account with operations: the newest account_op_seq_no + 1 of its
 * hafd.account_operations rows up to the context's block. Read by
 * hafbe_backend.get_account_ops_count(), so /accounts/{a} does not plan against
 * hafd.account_operations, whose first plan in a backend opens every segment file
 * of the table and of its indexes.
 *
 * Created outside the context-creation block so that a deployment whose context
 * already exists gets it on reinstall. A forking context's table is filled to its
 * current block before it is registered, with negative hive_rowids: see
 * wallet_stats_by_day in hafbe_app.sql. Rows filled this way are not reverted if a
 * fork later reverts a block the context had already processed at the upgrade. A
 * context that is not forking yet is filled by finalize_account_ops_count().
 */
DO $$
DECLARE
  __current_block      INT;
  __irreversible_block INT;
BEGIN
  IF to_regclass('hafbe_app.account_ops_count') IS NOT NULL THEN
    RETURN;
  END IF;

  -- Autovacuum settings as for hafbe_app's history tables (hafbe_app.sql), and
  -- a lower update-driven trigger too: live sync updates these rows far more
  -- often than it inserts new ones.
  CREATE TABLE hafbe_app.account_ops_count (
    account_id INT    NOT NULL,            -- Account ID (FK to hive.accounts_view)
    ops_count  INT    NOT NULL,            -- Newest account_op_seq_no + 1
    hive_rowid BIGINT NOT NULL DEFAULT 0,  -- HAF row identity, see above

    CONSTRAINT pk_account_ops_count PRIMARY KEY (account_id)
  ) WITH (
    autovacuum_vacuum_insert_scale_factor = 0.005,
    autovacuum_vacuum_scale_factor = 0.01,
    autovacuum_freeze_min_age = 0
  );

  IF hive.app_is_forking('hafbe_app') THEN
    __current_block      := hive.app_get_current_block_num('hafbe_app');
    __irreversible_block := LEAST(__current_block, hive.app_get_irreversible_block());

    INSERT INTO hafbe_app.account_ops_count (account_id, ops_count, hive_rowid)
    SELECT c.account_id, c.ops_count, -1 - c.account_id
    FROM hafbe_app.account_ops_counts_until(__irreversible_block) c;

    IF __current_block > __irreversible_block THEN
      PERFORM hafbe_app.process_account_ops_count(__irreversible_block + 1, __current_block);

      UPDATE hafbe_app.account_ops_count
      SET hive_rowid = -1 - account_id
      WHERE hive_rowid = 0;
    END IF;
  END IF;

  PERFORM hive.app_register_table( 'hafbe_app', 'account_ops_count', 'hafbe_app' );
END
$$;

RESET ROLE;
