SET ROLE hafbe_owner;

/*
 * Witness Vote and Proxy Processing Functions
 *
 * These VOLATILE functions process witness votes, proxy assignments, and account
 * expirations. They are called row-by-row from hafbe_app.process_witness_votes()
 * in operation order (by source_op).
 *
 * WHY ROW-BY-ROW PROCESSING:
 *   Operations have complex interdependencies that require sequential processing:
 *   1. Setting a proxy deletes all existing witness votes
 *   2. Clearing a proxy allows voting again
 *   3. Expired accounts lose all votes and proxies
 *
 *   Example sequence that MUST be processed in order:
 *     Op 100: Vote for witness A
 *     Op 200: Set proxy to X (deletes vote for A)
 *     Op 300: Clear proxy
 *     Op 400: Vote for witness B
 *   Final state: Only vote for B exists
 *
 *   Batch processing would incorrectly delete vote B (cast after proxy cleared).
 *
 * TABLES MODIFIED:
 *   - hafbe_app.witness_votes_history: Complete vote change history
 *   - hafbe_app.current_witness_votes: Current active witness votes
 *   - hafbe_app.account_proxies_history: Complete proxy change history
 *   - hafbe_app.current_account_proxies: Current proxy assignments
 */


/*
 * ===================================================================================
 * process_vote_op
 * ===================================================================================
 * PURPOSE: Process a single account_witness_vote_operation.
 *
 * JSON STRUCTURE (body_value, no type wrapper):
 *   { "account": "voter", "witness": "witness-name", "approve": true/false }
 *
 * BEHAVIOR:
 *   1. Always insert into witness_votes_history (for historical tracking)
 *   2. If approve=TRUE: Upsert into current_witness_votes
 *   3. If approve=FALSE: Delete from current_witness_votes
 *
 * PARAMETERS:
 *   _body: Operation body_value JSONB (inner value, no type wrapper)
 *   _id: Operation ID (source_op for history tracking)
 */
CREATE OR REPLACE FUNCTION hafbe_backend.process_vote_op(
    _body JSONB,
    _id   BIGINT
)
RETURNS VOID
LANGUAGE 'plpgsql' VOLATILE
AS $$
DECLARE
  __voter_id   INT     := (SELECT av.id FROM hafbe_app.accounts_view av WHERE av.name = _body ->> 'account');
  __witness_id INT     := (SELECT av.id FROM hafbe_app.accounts_view av WHERE av.name = _body ->> 'witness');
  __approve    BOOLEAN := (_body ->> 'approve')::BOOLEAN;
BEGIN
  /*
   * Step 1: Record in history (all votes, regardless of approve status)
   */
  INSERT INTO hafbe_app.witness_votes_history (witness_id, voter_id, approve, source_op)
  VALUES (__witness_id, __voter_id, __approve, _id);

  /*
   * Step 2: Update current state based on approve flag
   */
  IF __approve THEN
    -- Vote approved: upsert into current_witness_votes
    INSERT INTO hafbe_app.current_witness_votes (witness_id, voter_id, source_op)
    VALUES (__witness_id, __voter_id, _id)
    ON CONFLICT ON CONSTRAINT pk_current_witness_votes DO UPDATE SET
      source_op = EXCLUDED.source_op;
  ELSE
    -- Vote removed: delete from current_witness_votes
    DELETE FROM hafbe_app.current_witness_votes cwv
    WHERE cwv.witness_id = __witness_id
      AND cwv.voter_id = __voter_id;
  END IF;
END
$$;


/*
 * ===================================================================================
 * process_proxy_ops
 * ===================================================================================
 * PURPOSE: Process account_witness_proxy_operation or proxy_cleared_operation.
 *
 * JSON STRUCTURE (body_value, no type wrapper):
 *   { "account": "account-name", "proxy": "proxy-name" }
 *
 * BEHAVIOR:
 *   When setting proxy (_proxy=TRUE):
 *     1. Insert into account_proxies_history
 *     2. Upsert into current_account_proxies
 *     3. CASCADE: Delete ALL current witness votes for this account
 *        (because proxied accounts cannot vote directly)
 *     4. Record deleted votes in witness_votes_history as approve=FALSE
 *
 *   When clearing proxy (_proxy=FALSE):
 *     1. Insert into account_proxies_history
 *     2. Delete from current_account_proxies
 *
 * PARAMETERS:
 *   _body: Operation body_value JSONB (inner value, no type wrapper)
 *   _id: Operation ID (source_op for history tracking)
 *   _proxy: TRUE if setting proxy, FALSE if clearing proxy
 *
 * IMPORTANT: The cascade deletion of votes when setting proxy is critical.
 *   On the Hive blockchain, an account with a proxy cannot vote directly for
 *   witnesses - their voting power goes to whoever they proxy to.
 */
CREATE OR REPLACE FUNCTION hafbe_backend.process_proxy_ops(
    _body  JSONB,
    _id    BIGINT,
    _proxy BOOLEAN
)
RETURNS VOID
LANGUAGE 'plpgsql' VOLATILE
AS $$
DECLARE
  __account_id INT := (SELECT av.id FROM hafbe_app.accounts_view av WHERE av.name = _body ->> 'account');
  __proxy_id   INT := (SELECT av.id FROM hafbe_app.accounts_view av WHERE av.name = _body ->> 'proxy');
BEGIN
  /*
   * Skip if proxy account doesn't exist (can happen with empty proxy field)
   */
  IF __proxy_id IS NULL THEN
    RETURN;
  END IF;

  /*
   * Step 1: Record in history
   */
  INSERT INTO hafbe_app.account_proxies_history (account_id, proxy_id, proxy, source_op)
  VALUES (__account_id, __proxy_id, _proxy, _id);

  /*
   * Step 2: Update current state based on proxy flag
   */
  IF _proxy THEN
    -- Setting proxy: upsert into current_account_proxies
    INSERT INTO hafbe_app.current_account_proxies (account_id, proxy_id, source_op)
    VALUES (__account_id, __proxy_id, _id)
    ON CONFLICT ON CONSTRAINT pk_current_account_proxies DO UPDATE SET
      proxy_id  = EXCLUDED.proxy_id,
      source_op = EXCLUDED.source_op;

    /*
     * Step 3: CASCADE - Delete all witness votes for this account
     *
     * When an account sets a proxy, they can no longer vote directly.
     * All existing votes must be removed and recorded in history.
     */
    WITH deleted_votes AS (
      DELETE FROM hafbe_app.current_witness_votes cwv
      WHERE cwv.voter_id = __account_id
      RETURNING cwv.voter_id, cwv.witness_id
    )
    INSERT INTO hafbe_app.witness_votes_history (witness_id, voter_id, approve, source_op)
    SELECT dv.witness_id, dv.voter_id, FALSE, _id
    FROM deleted_votes dv;

  ELSE
    -- Clearing proxy: delete from current_account_proxies
    DELETE FROM hafbe_app.current_account_proxies cap
    WHERE cap.account_id = __account_id
      AND cap.proxy_id = __proxy_id;
  END IF;
END
$$;


/*
 * ===================================================================================
 * process_expired_accounts
 * ===================================================================================
 * PURPOSE: Process declined_voting_rights_operation or expired_account_notification_operation.
 *
 * JSON STRUCTURE (body_value, no type wrapper):
 *   { "account": "account-name" }
 *
 * BEHAVIOR:
 *   When an account expires or declines voting rights:
 *     1. Delete ALL current proxies for this account, record in history
 *     2. Delete ALL current witness votes for this account, record in history
 *
 * PARAMETERS:
 *   _body: Operation body_value JSONB (inner value, no type wrapper)
 *   _id: Operation ID (source_op for history tracking)
 *
 * NOTE: Both declined_voting_rights and expired_account_notification trigger
 *   the same cleanup - the account loses all voting-related state.
 */
CREATE OR REPLACE FUNCTION hafbe_backend.process_expired_accounts(
    _body JSONB,
    _id   BIGINT
)
RETURNS VOID
LANGUAGE 'plpgsql' VOLATILE
AS $$
DECLARE
  __account_id INT := (SELECT av.id FROM hafbe_app.accounts_view av WHERE av.name = _body ->> 'account');
BEGIN
  /*
   * Step 1: Delete all proxies and record in history
   */
  WITH deleted_proxies AS (
    DELETE FROM hafbe_app.current_account_proxies cap
    WHERE cap.account_id = __account_id
    RETURNING cap.account_id, cap.proxy_id
  )
  INSERT INTO hafbe_app.account_proxies_history (account_id, proxy_id, proxy, source_op)
  SELECT dp.account_id, dp.proxy_id, FALSE, _id
  FROM deleted_proxies dp;

  /*
   * Step 2: Delete all witness votes and record in history
   */
  WITH deleted_votes AS (
    DELETE FROM hafbe_app.current_witness_votes cwv
    WHERE cwv.voter_id = __account_id
    RETURNING cwv.voter_id, cwv.witness_id
  )
  INSERT INTO hafbe_app.witness_votes_history (witness_id, voter_id, approve, source_op)
  SELECT dv.witness_id, dv.voter_id, FALSE, _id
  FROM deleted_votes dv;

  -- NOTE: proposal-vote cleanup for this account is handled by
  -- process_proposal_expired_account inside process_proposals' row-by-row
  -- loop, NOT here. Doing it from the witness processor caused a fresh-sync
  -- ordering bug: in MASSIVE mode the witness processor runs before the
  -- proposal processor, so the proposal vote being deleted would not yet
  -- exist in current_proposal_votes.
END
$$;


RESET ROLE;
