SET ROLE hafbe_owner;

/** openapi:paths
/sync-status:
  get:
    tags:
      - Other
    summary: Get haf_block_explorer''s sync status
    description: |
      Get the last block fully processed by haf_block_explorer as an object
      containing both the block number and its timestamp (UTC). This is the
      uniform HAF-app sync/health endpoint: the timestamp lets a consumer
      compute staleness with a single call (`age = now() - last_block_time`)
      without needing a separate head-block reference. Supersedes the
      deprecated `/last-synced-block`.

      haf_block_explorer installs multiple HAF contexts (its own plus the
      balance tracker and reputation tracker sub-apps); the reported block is
      the least current block across those contexts, i.e. the lagging
      context, since that is what bounds the freshness of the API''s answers.

      SQL example
      * `SELECT * FROM hafbe_endpoints.get_hafbe_sync_status();`

      REST call example
      * `GET ''https://%1$s/hafbe-api/sync-status''`
    operationId: hafbe_endpoints.get_hafbe_sync_status
    responses:
      '200':
        description: |
          Last block processed by haf_block_explorer and its timestamp.
          `last_block_time` is null if no block has been processed yet.

          * Returns `JSON`
        content:
          application/json:
            schema:
              type: object
              x-sql-datatype: JSON
              properties:
                last_block_num:
                  type: integer
                  description: least block number processed across the app''s HAF contexts
                last_block_time:
                  type: string
                  format: date-time
                  description: UTC timestamp of that block
            example:
              last_block_num: 5000000
              last_block_time: '2016-09-15T19:47:21'
 */
-- openapi-generated-code-begin
DROP FUNCTION IF EXISTS hafbe_endpoints.get_hafbe_sync_status;
CREATE OR REPLACE FUNCTION hafbe_endpoints.get_hafbe_sync_status()
RETURNS JSON
-- openapi-generated-code-end
LANGUAGE 'plpgsql' STABLE
AS
$$
/*
================================================================================
ENDPOINT: get_hafbe_sync_status
================================================================================
PURPOSE:
  Returns the app's last fully-processed block number together with that
  block's timestamp, so monitors and health checks can judge freshness in one
  call. This is the HAF-wide uniform sync-status shape (see also the
  deprecated /last-synced-block, which returns only the bare block number).

DATA SOURCE:
  hafbe_backend.sync_status() — the LEAST current_block_num across the app's
  HAF contexts (hafbe_app plus the balance tracker and reputation tracker
  sub-app contexts, whose names are baked in at install time), joined to
  hafd.blocks for that block's created_at.

CACHING:
  No cache (max-age=0): used for real-time sync-status / health monitoring.

RETURN: JSON {"last_block_num": INT, "last_block_time": TEXT|null}
================================================================================
*/
BEGIN
  -- No cache - sync status needs real-time accuracy
  PERFORM set_config('response.headers', '[{"Cache-Control": "public, max-age=0"}]', true);

  RETURN hafbe_backend.sync_status();
END
$$;

RESET ROLE;
