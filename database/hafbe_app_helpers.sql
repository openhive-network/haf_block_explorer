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

CREATE OR REPLACE FUNCTION hafbe_app.process_blocks(
    _context_name hive.context_name,
    _block_range hive.blocks_range, 
    _logs BOOLEAN = true
)
RETURNS VOID
LANGUAGE 'plpgsql' VOLATILE
AS
$$
BEGIN
  IF hive.get_current_stage_name(_context_name) = 'MASSIVE_PROCESSING' THEN
    CALL hafbe_app.massive_processing(_block_range.first_block, _block_range.last_block, _logs);
    PERFORM hive.app_request_table_vacuum('hafbe_app.current_witness_votes', interval '30 minutes');
    PERFORM hive.app_request_table_vacuum('hafbe_app.current_witnesses', interval '30 minutes');
    PERFORM hive.app_request_table_vacuum('hafbe_app.current_account_proxies', interval '30 minutes');
    
    RETURN;
  END IF;
  IF NOT hafbe_app.isIndexesCreated() THEN
    PERFORM hafbe_indexes.create_hafbe_indexes();
  END IF;
  CALL hafbe_app.single_processing(_block_range.first_block, _logs);
END
$$;

CREATE OR REPLACE PROCEDURE hafbe_app.massive_processing(
    IN _from INT,
    IN _to INT,
    IN _logs BOOLEAN
)
LANGUAGE 'plpgsql'
AS
$$
DECLARE
  __start_ts timestamptz;
  __end_ts   timestamptz;
BEGIN
  PERFORM set_config('synchronous_commit', 'OFF', false);

  IF _logs THEN
    RAISE NOTICE 'Hafbe is attempting to process a block range: <%, %>', _from, _to;
    __start_ts := clock_timestamp();
  END IF;

  PERFORM hafbe_app.process_block_range_data_a(_from, _to);
  PERFORM hafbe_app.process_block_range_data_b(_from, _to);
  PERFORM hafbe_app.process_block_range_data_c(_from, _to);

  IF _logs THEN
    __end_ts := clock_timestamp();
    RAISE NOTICE 'Hafbe processed block range: <%, %> successfully in % s
    ', _from, _to, (extract(epoch FROM __end_ts - __start_ts));
  END IF;
END
$$;

CREATE OR REPLACE PROCEDURE hafbe_app.single_processing(
    IN _block INT,
    IN _logs BOOLEAN
)
LANGUAGE 'plpgsql'
AS
$$
DECLARE
  __start_ts timestamptz;
  __end_ts   timestamptz;
BEGIN
  PERFORM set_config('synchronous_commit', 'ON', false);

  IF _logs THEN
    RAISE NOTICE 'Hafbe processing block: %...', _block;
    __start_ts := clock_timestamp();
  END IF;

  PERFORM hafbe_app.process_block_range_data_a(_block, _block);
  PERFORM hafbe_app.process_block_range_data_b(_block, _block);
  PERFORM hafbe_app.process_block_range_data_c(_block, _block);

  IF _logs THEN
    __end_ts := clock_timestamp();
    RAISE NOTICE 'Hafbe processed block % successfully in % s
    ', _block, (extract(epoch FROM __end_ts - __start_ts));
  END IF;
END
$$;


CREATE OR REPLACE FUNCTION hafbe_app.log_and_process_blocks(
    _context_hafbe hive.context_name,
    _context_btracker hive.context_name,
    _block_range hive.blocks_range
)
RETURNS VOID
LANGUAGE 'plpgsql' VOLATILE
AS
$$
DECLARE
  __start_ts timestamptz;
  __end_ts   timestamptz;
  _time JSONB = '{}'::JSONB;
BEGIN
  IF hive.get_current_stage_name(_context_hafbe) = 'MASSIVE_PROCESSING' THEN
    RAISE NOTICE '[MASSIVE] Attempting to process a block range: <%, %>', _block_range.first_block, _block_range.last_block;
  ELSE
    RAISE NOTICE '[SINGLE]  Attempting to process block: <%>', _block_range.first_block;
  END IF;

  SELECT hafbe_backend.get_sync_time(_time, 'time_on_start') INTO _time;
  PERFORM hafbe_app.process_blocks(_context_hafbe, _block_range, false);
  SELECT hafbe_backend.get_sync_time(_time, 'hafbe') INTO _time;

  SELECT hafbe_backend.get_sync_time(_time, 'time_on_start') INTO _time;
  PERFORM btracker_process_blocks(_context_btracker, _block_range, false);
  SELECT hafbe_backend.get_sync_time(_time, 'btracker') INTO _time;

  SELECT hafbe_backend.get_sync_time(_time, 'time_on_start') INTO _time;
  PERFORM hive.app_state_providers_update(_block_range.first_block, _block_range.last_block, _context_hafbe);
  SELECT hafbe_backend.get_sync_time(_time, 'state_provider') INTO _time;

  INSERT INTO hafbe_app.sync_time_logs (block_num, time_json) VALUES (_block_range.first_block, _time);

  RAISE NOTICE 'Processed blocks in % seconds',
  ROUND(EXTRACT(epoch FROM (SELECT clock_timestamp() - last_reported_at FROM hafbe_app.app_status LIMIT 1)), 3);
  UPDATE hafbe_app.app_status SET last_reported_at = clock_timestamp();

  RAISE NOTICE 'Block processing running for % minutes
  ',
  ROUND((EXTRACT(epoch FROM (SELECT clock_timestamp() - started_processing_at FROM hafbe_app.app_status LIMIT 1)) / 60)::NUMERIC, 2);
  
  IF (NOW() - (SELECT last_updated_at FROM hafbe_app.witnesses_cache_config LIMIT 1)) >= 
    (SELECT update_interval FROM hafbe_app.witnesses_cache_config LIMIT 1) THEN
    RAISE NOTICE 'Process witness cache...';

    __start_ts := clock_timestamp();
    CALL hafbe_app.update_witnesses_cache();
    __end_ts := clock_timestamp();

    RAISE NOTICE 'Witness cache processing done in % s', (extract(epoch FROM __end_ts - __start_ts));
  END IF;

END
$$;

RESET ROLE;
