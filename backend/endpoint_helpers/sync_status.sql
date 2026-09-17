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
-- The block's timestamp comes from HAF's public hive.get_app_current_block_age()
-- over the same context group (its minimum is the lagging context's block, the
-- same block __block_num names) rather than from hafd.blocks (which only holds
-- irreversible blocks and so returned a null time for a forking context's
-- freshly processed head block) or from hafbe_app.blocks_view (which HAF
-- recreates under an ACCESS EXCLUSIVE lock on every context attach/detach,
-- stalling the endpoint behind the app's iteration transaction whenever the app
-- catches up). See the comment in the function body.
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
        WHERE name IN ('hafbe_app', %1$L, %2$L)
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

      -- Block timestamp via HAF's public API. hive.get_app_current_block_age()
      -- reads hafd.contexts + hafd.blocks + hafd.blocks_reversible, so a freshly
      -- processed, still-reversible head block resolves, and it touches no
      -- context view: HAF recreates <ctx>.blocks_view under an ACCESS EXCLUSIVE
      -- lock on every context attach/detach (which the HAF app loop does when
      -- switching stages to catch up), so a lookup through the view queues
      -- behind the app's whole iteration transaction (seen: 17 s -> statement
      -- timeouts and haproxy check failures). now() is the transaction
      -- timestamp on both sides of the subtraction, so now() - age is the
      -- block's created_at exactly (HAF runs with a UTC session time zone).
      -- Block 0 (pre-sync) has no row and HAF reports its age from the epoch,
      -- hence the explicit null.
      RETURN json_build_object(
        'last_block_num', __block_num,
        'last_block_time', CASE WHEN __block_num > 0 THEN
          to_char(now() - hive.get_app_current_block_age(ARRAY['hafbe_app', %1$L, %2$L]::hive.contexts_group),
                  'YYYY-MM-DD"T"HH24:MI:SS')
        END
      );
    END
    $pb$;
  $BODY$, __btracker_schema, __reptracker_schema);
END
$$;

RESET ROLE;
