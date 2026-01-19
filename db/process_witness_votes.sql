SET ROLE hafbe_owner;

/*
 * process_witness_votes: Processes witness votes, proxies, and expired accounts.
 *
 * Core operations: Handles account_witness_vote, account_witness_proxy,
 * proxy_cleared, declined_voting_rights, and expired_account_notification operations.
 *
 * Updates tables:
 *   - hafbe_app.witness_votes_history: Complete vote change history
 *   - hafbe_app.current_witness_votes: Current active witness votes
 *   - hafbe_app.account_proxies_history: Complete proxy change history
 *   - hafbe_app.current_account_proxies: Current proxy assignments
 *
 * WHY ROW-BY-ROW PROCESSING (not batch):
 *   Operations have complex interdependencies that require sequential processing:
 *
 *   1. Setting a proxy DELETES all existing witness votes for that account
 *   2. Clearing a proxy allows the account to vote directly again
 *   3. Expired/declined accounts lose ALL votes and proxies
 *
 *   Example sequence that MUST be processed in order:
 *     Op 100: Vote for witness A
 *     Op 200: Set proxy to X (cascade: deletes vote for A)
 *     Op 300: Clear proxy
 *     Op 400: Vote for witness B
 *
 *   Correct final state: Only vote for B exists
 *
 *   If processed as batch (all votes, then all proxies):
 *     - Section 1: Insert votes for A and B
 *     - Section 2: Set proxy (deletes ALL votes including B!)
 *     - Wrong final state: No votes
 *
 *   Therefore, operations MUST be processed in operation_id order.
 */
CREATE OR REPLACE FUNCTION hafbe_app.process_witness_votes(_from INT, _to INT)
RETURNS VOID
LANGUAGE 'plpgsql' VOLATILE
SET from_collapse_limit = 16
SET join_collapse_limit = 16
SET jit = OFF
AS $$
DECLARE
  -- Cache operation type IDs to avoid repeated function calls
  _op_account_witness_vote         INT := hafbe_backend.op_account_witness_vote();
  _op_account_witness_proxy        INT := hafbe_backend.op_account_witness_proxy();
  _op_proxy_cleared                INT := hafbe_backend.op_proxy_cleared();
  _op_declined_voting_rights       INT := hafbe_backend.op_declined_voting_rights();
  _op_expired_account_notification INT := hafbe_backend.op_expired_account_notification();
  _result                          INT;
BEGIN

  /*
   * ===================================================================================
   * Main Processing Loop
   * ===================================================================================
   * Fetch all relevant operations in the block range and process them IN ORDER.
   *
   * The ORDER BY bc.id is CRITICAL - it ensures operations are processed in the
   * sequence they occurred on the blockchain, preserving the correct cascading
   * effects between votes and proxies.
   *
   * Each operation type is dispatched to its specialized handler function:
   *   - account_witness_vote      -> process_vote_op()
   *   - account_witness_proxy     -> process_proxy_ops(..., TRUE)
   *   - proxy_cleared             -> process_proxy_ops(..., FALSE)
   *   - declined_voting_rights    -> process_expired_accounts()
   *   - expired_account_notification -> process_expired_accounts()
   *
   * The handler functions are VOLATILE and perform DML (INSERT/UPDATE/DELETE).
   * They are called via a CASE expression in SELECT, which processes each row.
   */
  WITH proxy_ops AS MATERIALIZED (
    SELECT
      ov.body     AS body,
      ov.id       AS id,
      ov.block_num,
      ov.op_type_id AS op_type
    FROM hafbe_app.operations_view ov
    WHERE ov.op_type_id IN (
      _op_account_witness_vote,
      _op_account_witness_proxy,
      _op_proxy_cleared,
      _op_declined_voting_rights,
      _op_expired_account_notification
    )
    AND ov.block_num BETWEEN _from AND _to
  ),

  /*
   * Process each operation by dispatching to the appropriate handler.
   *
   * IMPORTANT: The ORDER BY id ensures operations are processed sequentially
   * in the order they appeared on the blockchain.
   */
  balance_change AS (
    SELECT
      bc.id,
      (
        CASE
          WHEN bc.op_type = _op_account_witness_vote THEN
            hafbe_backend.process_vote_op(bc.body, bc.id)

          WHEN bc.op_type = _op_account_witness_proxy THEN
            hafbe_backend.process_proxy_ops(bc.body, bc.id, TRUE)

          WHEN bc.op_type = _op_proxy_cleared THEN
            hafbe_backend.process_proxy_ops(bc.body, bc.id, FALSE)

          WHEN bc.op_type = _op_declined_voting_rights
            OR bc.op_type = _op_expired_account_notification THEN
            hafbe_backend.process_expired_accounts(bc.body, bc.id)
        END
      ) AS result
    FROM proxy_ops bc
    ORDER BY bc.id
  )

  /*
   * Force evaluation of all rows (and thus all handler function calls)
   * by counting the results.
   */
  SELECT COUNT(*) FROM balance_change INTO _result;

END
$$;


/*
 * ===================================================================================
 * process_witness_votes_cache
 * ===================================================================================
 * PURPOSE: Refreshes cached witness vote statistics for fast API queries.
 *
 * This function rebuilds several cache tables used by the witness-related
 * API endpoints. It should be called periodically (e.g., every few minutes)
 * to keep the cached statistics up-to-date.
 *
 * CACHE TABLES UPDATED:
 *   - account_vest_stats_cache: Vesting power per account (own + proxied)
 *   - witness_votes_cache: Total votes and voter count per witness
 *   - witness_rank_cache: Witness rankings by vote weight
 *   - witness_votes_change_cache: Daily vote changes (for "24h change" stats)
 *
 * NOTE: This uses DELETE + INSERT (full refresh) rather than incremental updates
 *   for simplicity and to avoid accumulating stale data.
 */
CREATE OR REPLACE FUNCTION hafbe_app.process_witness_votes_cache()
RETURNS VOID
LANGUAGE 'plpgsql' VOLATILE
SET from_collapse_limit = 16
SET join_collapse_limit = 16
SET jit = OFF
AS $$
DECLARE
  -- Find the first block of "today" for daily change calculations
  _first_block_num INT := (
    SELECT num
    FROM hive.blocks_view
    WHERE created_at <= 'today'::DATE
    ORDER BY num DESC
    LIMIT 1
  );
BEGIN

  /*
   * ===================================================================================
   * Cache 1: Account Vest Stats
   * ===================================================================================
   * Caches vesting power statistics for each account:
   *   - vests: Total effective vesting power (own + proxied to this account)
   *   - account_vests: Account's own vesting power
   *   - proxied_vests: Vesting power proxied to this account by others
   */
  DELETE FROM hafbe_app.account_vest_stats_cache;

  INSERT INTO hafbe_app.account_vest_stats_cache (account_id, vests, account_vests, proxied_vests)
  SELECT
    account_id,
    vests,
    account_vests,
    proxied_vests
  FROM hafbe_backend.account_vest_stats_view;


  /*
   * ===================================================================================
   * Cache 2: Witness Votes
   * ===================================================================================
   * Caches total vote weight and voter count per witness.
   * Uses the account_vest_stats_cache we just populated.
   */
  DELETE FROM hafbe_app.witness_votes_cache;

  INSERT INTO hafbe_app.witness_votes_cache (witness_id, votes, voters_num)
  SELECT
    cwv.witness_id,
    SUM(avs.vests)::BIGINT AS votes,
    COUNT(*)               AS voters_num
  FROM hafbe_backend.current_witness_votes_view cwv
  JOIN hafbe_app.account_vest_stats_cache avs ON avs.account_id = cwv.voter_id
  GROUP BY cwv.witness_id;


  /*
   * ===================================================================================
   * Cache 3: Witness Rank
   * ===================================================================================
   * Caches witness rankings based on vote weight.
   * Ranking criteria (in order):
   *   1. Total votes (DESC)
   *   2. Number of voters (DESC)
   *   3. Witness ID (DESC) - tiebreaker
   */
  DELETE FROM hafbe_app.witness_rank_cache;

  INSERT INTO hafbe_app.witness_rank_cache (witness_id, rank)
  SELECT
    cw.witness_id,
    ROW_NUMBER() OVER (
      ORDER BY
        COALESCE(wv.votes, 0) DESC,
        COALESCE(wv.voters_num, 0) DESC,
        cw.witness_id DESC
    ) AS rank
  FROM hafbe_app.current_witnesses cw
  LEFT JOIN hafbe_app.witness_votes_cache wv ON wv.witness_id = cw.witness_id;


  /*
   * ===================================================================================
   * Cache 4: Witness Votes Daily Change
   * ===================================================================================
   * Caches the change in votes and voters for each witness since start of today.
   * Used for "24h change" statistics in the API.
   *
   * Calculation:
   *   - Positive vests for approve=TRUE votes
   *   - Negative vests for approve=FALSE votes
   *   - Sum gives net change in vote weight
   */
  DELETE FROM hafbe_app.witness_votes_change_cache;

  INSERT INTO hafbe_app.witness_votes_change_cache (witness_id, votes_daily_change, voters_num_daily_change)
  SELECT
    wvhc.witness_id,
    SUM(CASE WHEN wvhc.approve THEN avs.vests ELSE -1 * avs.vests END)::BIGINT AS votes_daily_change,
    SUM(CASE WHEN wvhc.approve THEN 1 ELSE -1 END)::INT                        AS voters_num_daily_change
  FROM hafbe_backend.witness_votes_history_view wvhc
  JOIN hafbe_app.account_vest_stats_cache avs ON avs.account_id = wvhc.voter_id
  WHERE wvhc.source_op_block >= _first_block_num
  GROUP BY wvhc.witness_id;

END
$$;

RESET ROLE;
