SET ROLE hafbe_owner;

-- ============================================================================
-- Sync Status Helper
-- ============================================================================
-- hafbe_backend.sync_status() — the last fully-processed block as
-- {last_block_num, last_block_time}, for the /sync-status endpoint (the
-- HAF-wide uniform health/freshness API that supersedes the bare-integer
-- /last-synced-block). The timestamp lets consumers compute staleness with a
-- single call (age = now() - last_block_time) instead of needing a second
-- head-block reference.
--
-- haf_block_explorer installs multiple HAF contexts: its own ('hafbe_app',
-- hardcoded repo-wide) plus the balance tracker and reputation tracker
-- sub-apps, whose context names equal their install-time schema names
-- (BTRACKER_SCHEMA / REPTRACKER_SCHEMA in install_app.sh). The reported block
-- is the LEAST current_block_num across those contexts — the lagging context
-- is what determines how fresh the API's answers actually are.
--
-- The sub-app context names are baked in at install time: install_app.sh
-- passes them via the custom.btracker_schema / custom.reptracker_schema GUCs
-- (same pattern as custom.is_forking / custom.swagger_url) and this DO block
-- formats them into the function body.
--
-- The block's timestamp is read through hafbe_app.blocks_view rather than
-- hafd.blocks: these are forking contexts, so once caught up the current block
-- usually still sits in hafd.blocks_reversible for a few hundred ms before OBI
-- makes it irreversible. Joining hafd.blocks alone returned a null time in that
-- window, which health checks read as "no block processed yet" and flapped the
-- backend. hafbe_app's view is valid for the sub-app contexts' blocks too: the
-- LEAST block is at or below hafbe_app's current block, so it is either
-- already in hafd.blocks or still held in hafd.blocks_reversible (HAF only
-- prunes reversible rows below every context's irreversible block), and the
-- view exposes both. The pre-sync case (block 0) still yields a null time.
--
-- The lookup is deliberately parameterized on a plain variable: joining a
-- forking context's blocks_view on another relation's column defeats predicate
-- pushdown into the view's UNION ALL and plans as a hash join over all of
-- hafd.blocks (measured at 74 s on a mainnet node), whereas
-- `WHERE num = <param>` is an index lookup in both branches.
-- ============================================================================

DO $$
DECLARE
  __btracker_schema TEXT := current_setting('custom.btracker_schema');
  __reptracker_schema TEXT := current_setting('custom.reptracker_schema');
BEGIN
  EXECUTE format(
  $BODY$
    CREATE OR REPLACE FUNCTION hafbe_backend.sync_status()
    RETURNS JSON
    LANGUAGE 'plpgsql' STABLE
    AS
    $pb$
    DECLARE
      __block_num INT := (
        SELECT current_block_num
        FROM hafd.contexts
        WHERE name IN ('hafbe_app', %L, %L)
        ORDER BY current_block_num ASC
        LIMIT 1
      );
    BEGIN
      -- Fail fast during HAF massive sync: hafd.blocks' PK is dropped for the
      -- duration (hive.disable_indexes_of_irreversible), so the lookup below
      -- would seq-scan the largest table in the database. Health-check agents
      -- gate on is_instance_ready() before calling APIs; this guard protects
      -- any caller that does not (e.g. a raw haproxy httpchk) by erroring in
      -- milliseconds instead of stalling.
      IF NOT hive.is_instance_ready() THEN
        RAISE EXCEPTION 'HAF instance is not ready (massive sync in progress)'
          USING ERRCODE = '55000';
      END IF;

      RETURN json_build_object(
        'last_block_num', __block_num,
        'last_block_time', to_char(
          (SELECT b.created_at FROM hafbe_app.blocks_view b WHERE b.num = __block_num),
          'YYYY-MM-DD"T"HH24:MI:SS')
      );
    END
    $pb$;
  $BODY$, __btracker_schema, __reptracker_schema);
END
$$;

RESET ROLE;
