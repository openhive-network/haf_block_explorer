-- noqa: disable=CP03

SET ROLE hafbe_owner;

--- Helper function telling application main-loop to continue execution.
CREATE OR REPLACE FUNCTION hafbe_app.continueProcessing()
RETURNS BOOLEAN
LANGUAGE 'plpgsql' STABLE
AS
$$
BEGIN
  RETURN continue_processing FROM hafbe_app.app_status LIMIT 1;
END
$$;

CREATE OR REPLACE FUNCTION hafbe_app.allowProcessing()
RETURNS VOID
LANGUAGE 'plpgsql' VOLATILE
AS
$$
BEGIN
  UPDATE hafbe_app.app_status SET continue_processing = True;
END
$$;

--- Helper function to be called from separate transaction (must be committed) 
--- to safely stop execution of the application.
CREATE OR REPLACE FUNCTION hafbe_app.stopProcessing()
RETURNS VOID
LANGUAGE 'plpgsql' VOLATILE
AS
$$
BEGIN
  UPDATE hafbe_app.app_status SET continue_processing = False;
END
$$;

CREATE OR REPLACE FUNCTION hafbe_app.isIndexesCreated()
RETURNS BOOLEAN
LANGUAGE 'plpgsql' STABLE
AS
$$
BEGIN
  RETURN EXISTS(
      SELECT true FROM pg_index WHERE indexrelid = 
      (
        SELECT oid FROM pg_class WHERE relname = 'account_proxies_history_account_id'
      )
    );
END
$$;

CREATE OR REPLACE FUNCTION hafbe_app.isCommentSearchIndexesCreated()
RETURNS BOOLEAN
LANGUAGE 'plpgsql' STABLE
AS
$$
BEGIN
  RETURN EXISTS(
      SELECT true FROM pg_index WHERE indexrelid = 
      (
        SELECT oid FROM pg_class WHERE relname = 'hive_operations_comment_search_permlink_author'
      )
    );
END
$$;

CREATE OR REPLACE FUNCTION hafbe_app.isBlockSearchIndexesCreated()
RETURNS BOOLEAN
LANGUAGE 'plpgsql' STABLE
AS
$$
BEGIN
  RETURN EXISTS(
      SELECT true FROM pg_index WHERE indexrelid = 
      (
        SELECT oid FROM pg_class WHERE relname = 'hive_operations_vote_author_permlink'
      )
    );
END
$$;

CREATE OR REPLACE FUNCTION hafbe_app.generate_lock_key( _index_name TEXT)
RETURNS BIGINT
LANGUAGE 'plpgsql' IMMUTABLE
AS
$$
BEGIN
    RETURN ('x' || substring(md5(_index_name), 1, 16))::BIT(64)::BIGINT % 2147483647;
END
$$;

CREATE OR REPLACE PROCEDURE hafbe_app.create_context_if_not_exists(_appContext VARCHAR)
LANGUAGE 'plpgsql'
AS
$$
BEGIN
  IF NOT hive.app_context_exists(_appContext) THEN
    RAISE NOTICE 'Attempting to create a HAF application context...';
    PERFORM hive.app_create_context(
      _name => _appContext,
      _schema => _appContext,
      _is_forking => TRUE,
      _is_attached => FALSE
    );
    COMMIT;
  END IF;
END
$$;

CREATE OR REPLACE PROCEDURE hafbe_app.update_witnesses_cache()
AS
$function$
BEGIN
  RAISE NOTICE 'Updating witnesses caches';

  TRUNCATE TABLE hafbe_app.witness_voters_stats_cache;

  INSERT INTO hafbe_app.witness_voters_stats_cache (witness_id, voter_id, vests, account_vests, proxied_vests, timestamp)
  SELECT witness_id, voter_id, (vests)::BIGINT, (account_vests)::BIGINT, (proxied_vests)::BIGINT, timestamp
  FROM hafbe_views.voters_stats_view;

  RAISE NOTICE 'Updated witness voters cache';

  TRUNCATE TABLE hafbe_app.witness_votes_history_cache;

  INSERT INTO hafbe_app.witness_votes_history_cache (witness_id, voter_id, approve, timestamp, proxied_vests, account_vests)
    SELECT
      wvh.witness_id, wvh.voter_id, wvh.approve, wvh.timestamp, ((COALESCE(rpav.proxied_vests, 0)))::BIGINT AS proxied_vests,
      ((COALESCE(av.balance::BIGINT, 0) - COALESCE(dv.delayed_vests::BIGINT, 0)))::BIGINT AS account_vests
    FROM hafbe_app.witness_votes_history wvh
    LEFT JOIN current_account_balances av
      ON av.account = wvh.voter_id AND av.nai = 37
    LEFT JOIN account_withdraws dv
      ON dv.account = wvh.voter_id
    LEFT JOIN hafbe_views.voters_proxied_vests_sum_view rpav
    ON rpav.proxy_id = wvh.voter_id;

  RAISE NOTICE 'Updated witness voters history cache';

  TRUNCATE TABLE hafbe_app.witness_votes_cache;

  INSERT INTO hafbe_app.witness_votes_cache (witness_id, rank, votes, voters_num)
  SELECT witness_id, RANK() OVER (ORDER BY votes DESC, voters_num DESC, feed_updated_at DESC), votes, voters_num
  FROM (
    SELECT
      witness_id,
      (SUM(vests))::BIGINT AS votes,
      COUNT(1) AS voters_num,
      MAX(timestamp) AS feed_updated_at
    FROM hafbe_app.witness_voters_stats_cache
    GROUP BY witness_id
  ) vsv;

  RAISE NOTICE 'Updated witnesses cache';

  TRUNCATE TABLE hafbe_app.witness_votes_change_cache;

  INSERT INTO hafbe_app.witness_votes_change_cache (witness_id, votes_daily_change, voters_num_daily_change)
  SELECT
    witness_id,
    SUM(CASE WHEN wvhc.approve THEN wvhc.account_vests + wvhc.proxied_vests ELSE -1 * (wvhc.account_vests + wvhc.proxied_vests) END)::BIGINT,
    SUM(CASE WHEN wvhc.approve THEN 1 ELSE -1 END)::INT
  FROM hafbe_app.witness_votes_history_cache wvhc
  WHERE wvhc.timestamp >= 'today'::DATE
  GROUP BY wvhc.witness_id;

  RAISE NOTICE 'Updated witness change cache';

  UPDATE hafbe_app.witnesses_cache_config SET last_updated_at = NOW();
END
$function$
LANGUAGE 'plpgsql'
SET JIT = OFF
SET join_collapse_limit = 16
SET from_collapse_limit = 16;

RESET ROLE;
