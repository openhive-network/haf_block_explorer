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

CREATE OR REPLACE FUNCTION hafbe_app.storeLastProcessedBlock(_lastBlock INT)
RETURNS VOID
LANGUAGE 'plpgsql' VOLATILE
AS
$$
BEGIN
  UPDATE hafbe_app.app_status SET last_processed_block = _lastBlock;
END
$$;

CREATE OR REPLACE FUNCTION hafbe_app.lastProcessedBlock()
RETURNS INT
LANGUAGE 'plpgsql' STABLE
AS
$$
BEGIN
  RETURN last_processed_block FROM hafbe_app.app_status LIMIT 1;
END
$$;

CREATE OR REPLACE PROCEDURE hafbe_app.processBlock(_block INT, _appContext VARCHAR)
LANGUAGE 'plpgsql'
AS
$$
DECLARE
_time JSONB = '{}'::JSONB;
BEGIN
  SELECT hafbe_backend.get_sync_time(_time, 'time_on_start') INTO _time;
  PERFORM btracker_app.process_block_range_data_a(_block, _block);
  SELECT hafbe_backend.get_sync_time(_time, 'btracker_app_a') INTO _time;

  SELECT hafbe_backend.get_sync_time(_time, 'time_on_start') INTO _time;
  PERFORM btracker_app.process_block_range_data_b(_block, _block);
  SELECT hafbe_backend.get_sync_time(_time, 'btracker_app_b') INTO _time;

  SELECT hafbe_backend.get_sync_time(_time, 'time_on_start') INTO _time;
  PERFORM hafbe_app.process_block_range_data_a(_block, _block);
  SELECT hafbe_backend.get_sync_time(_time, 'hafbe_app_a') INTO _time;

  SELECT hafbe_backend.get_sync_time(_time, 'time_on_start') INTO _time;
  PERFORM hafbe_app.process_block_range_data_b(_block, _block);
  SELECT hafbe_backend.get_sync_time(_time, 'hafbe_app_b') INTO _time;

  SELECT hafbe_backend.get_sync_time(_time, 'time_on_start') INTO _time;
  PERFORM hafbe_app.process_block_range_data_c(_block, _block);
  SELECT hafbe_backend.get_sync_time(_time, 'hafbe_app_c') INTO _time;

  SELECT hafbe_backend.get_sync_time(_time, 'time_on_start') INTO _time;
  PERFORM hive.app_state_providers_update(_block, _block, _appContext);
  SELECT hafbe_backend.get_sync_time(_time, 'state_provider') INTO _time;

  INSERT INTO hafbe_app.sync_time_logs (block_num, time_json) VALUES (_block, _time);

  PERFORM hafbe_app.storeLastProcessedBlock(_block);

  RAISE NOTICE 'Block processing running for % minutes
  ',
  ROUND((EXTRACT(epoch FROM (SELECT NOW() - started_processing_at FROM hafbe_app.app_status LIMIT 1)) / 60)::NUMERIC, 2);

  COMMIT; -- For single block processing we want to commit all changes for each one.
END
$$;

CREATE OR REPLACE PROCEDURE hafbe_app.create_context_if_not_exists(_appContext VARCHAR)
LANGUAGE 'plpgsql'
AS
$$
BEGIN
  IF NOT hive.app_context_exists(_appContext) THEN
    RAISE NOTICE 'Attempting to create a HAF application context...';
    PERFORM hive.app_create_context(_appContext);
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
      ((COALESCE(av.balance, 0) - COALESCE(dv.delayed_vests, 0)))::BIGINT AS account_vests
    FROM hafbe_app.witness_votes_history wvh
    LEFT JOIN btracker_app.current_account_balances av
      ON av.account = wvh.voter_id AND av.nai = 37
    LEFT JOIN btracker_app.account_withdraws dv
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
