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
-- formats them into the function body. LEFT JOIN to hafd.blocks so the
-- pre-sync case (no processed block yet) still yields an object with a null
-- time rather than an error.
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
    BEGIN
      -- Fail fast during HAF massive sync: hafd.blocks' PK is dropped for the
      -- duration (hive.disable_indexes_of_irreversible), so the join below
      -- would seq-scan the largest table in the database. Health-check agents
      -- gate on is_instance_ready() before calling APIs; this guard protects
      -- any caller that does not (e.g. a raw haproxy httpchk) by erroring in
      -- milliseconds instead of stalling.
      IF NOT hive.is_instance_ready() THEN
        RAISE EXCEPTION 'HAF instance is not ready (massive sync in progress)'
          USING ERRCODE = '55000';
      END IF;

      RETURN (
        SELECT json_build_object(
          'last_block_num', c.current_block_num,
          'last_block_time', to_char(b.created_at, 'YYYY-MM-DD"T"HH24:MI:SS')
        )
        FROM hafd.contexts c
        LEFT JOIN hafd.blocks b ON b.num = c.current_block_num
        WHERE c.name IN ('hafbe_app', %L, %L)
        ORDER BY c.current_block_num ASC NULLS FIRST
        LIMIT 1
      );
    END
    $pb$;
  $BODY$, __btracker_schema, __reptracker_schema);
END
$$;

RESET ROLE;
