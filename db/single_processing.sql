SET ROLE hafbe_owner;

/**
 * single_processing()
 * -------------------
 * Process a single block during LIVE sync stage.
 * Uses synchronous_commit ON for data safety.
 *
 * Called for each new block after initial sync is complete.
 * Processes all operation types for the given block plus cache updates.
 *
 * @param _block  Block number to process
 * @param _logs   Enable progress logging
 *
 * Kept out of hafbe_app.sql so install_app.sh replaces it only after the
 * processing functions it calls: an install interrupted before them leaves the
 * previous single_processing calling the previous functions.
 */
CREATE OR REPLACE PROCEDURE hafbe_app.single_processing(
    IN _block INT,
    IN _logs BOOLEAN
)
LANGUAGE plpgsql
AS
$$
DECLARE
  __start_ts TIMESTAMPTZ;
  __end_ts   TIMESTAMPTZ;
BEGIN
  PERFORM set_config('synchronous_commit', 'ON', false);

  IF _logs THEN
    RAISE NOTICE 'Hafbe processing block: %...', _block;
    __start_ts := clock_timestamp();
  END IF;

  PERFORM hafbe_app.process_account_stats(_block, _block);
  PERFORM hafbe_app.process_account_ops_count(_block, _block);
  PERFORM hafbe_app.process_block_operations(_block, _block);
  PERFORM hafbe_app.process_transaction_stats(_block, _block);
  PERFORM hafbe_app.process_witness_stats(_block, _block);
  PERFORM hafbe_app.process_witness_votes(_block, _block);
  PERFORM hafbe_app.process_proposals(_block, _block);
  PERFORM hafbe_app.process_witness_votes_cache(_block);
  -- Must run after process_witness_votes_cache so account_vest_stats_cache
  -- is fresh for the same block before we join against it.
  PERFORM hafbe_app.process_proposal_vote_stats_cache();

  IF _logs THEN
    __end_ts := clock_timestamp();
    RAISE NOTICE 'Hafbe processed block % successfully in % s
    ', _block, (extract(epoch FROM __end_ts - __start_ts));
  END IF;
END
$$;

RESET ROLE;
