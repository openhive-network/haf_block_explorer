SET ROLE hafbe_owner;

/*
 * Proposal Operation Processing Functions
 * ---------------------------------------
 * Per-op VOLATILE handlers called row-by-row from hafbe_app.process_proposals()
 * in operation_id order. Mirrors the witness_operations.sql pattern.
 *
 * WHY ROW-BY-ROW PROCESSING
 *   Operations have cascading interdependencies via current_proposal_votes:
 *
 *     Op 100: alice approves proposal X (update_proposal_votes)
 *     Op 200: alice loses voting rights (decline / expired)
 *     Op 300: someone removes proposal X
 *
 *   Correct final state: no row for alice in current_proposal_votes, X is
 *   marked removed. If processed as batch (all votes, then all cleanups),
 *   the op-300 cleanup might run before op-100's insert lands, leaving a
 *   stale row.
 *
 * TABLES MODIFIED
 *   - hafbe_app.current_proposals     (lifecycle: create handled in batch
 *                                      pre-pass in process_proposals; update
 *                                      and remove handled here)
 *   - hafbe_app.proposal_votes_history (append-only)
 *   - hafbe_app.current_proposal_votes (active approvals)
 *   - hafbe_app.current_proposals.paid_amount (running payment total)
 *   - hafbe_app.current_proposals.total_budget (full-term payout, see below)
 */


/*
 * total_budget: the most a proposal can be paid over its whole term, at the
 * daily pay in force on each day (milli-HBD). STEP A of process_proposals sets
 * it at create; process_proposal_update_op adjusts it at each update's block
 * time. db/backfill_proposal_total_budget.sql replays the same two functions
 * over the chain's ops for rows an older install left NULL, so a fresh sync
 * and an upgrade compute the same value.
 *
 * Durations are fractional days. Each change is rounded to whole milli-HBD
 * once, so an update adds at most 1 milli-HBD of drift. NUMERIC, not BIGINT:
 * mainnet proposals 116 and 117 ask 999999999999999 HBD a day for 17 years,
 * about 6.4e21 milli-HBD, past BIGINT's 9.2e18.
 */
CREATE OR REPLACE FUNCTION hafbe_backend.proposal_term_pay(
    _daily_pay BIGINT,
    _from      TIMESTAMP,
    _to        TIMESTAMP
)
RETURNS NUMERIC
-- STRICT: NULL in, NULL out. Without it GREATEST(NULL, 0) would turn an unknown
-- date into 0 days and an update with an unknown block time would be ignored.
LANGUAGE sql IMMUTABLE STRICT
AS $$
  SELECT _daily_pay * GREATEST(EXTRACT(EPOCH FROM (_to - _from)), 0) / 86400;
$$;

/*
 * Budget after an update at block time _at that moves the pay from _old_pay to
 * _new_pay and the end from _old_end to _new_end. From s = _at clamped to
 * [_start_date, _old_end], the rest of the old term at the old pay is replaced
 * by the rest of the new term at the new pay. An update before the start
 * replaces the whole budget (s = start); one after the end changes nothing
 * (s = old end, and hived does not lengthen a term). A NULL budget stays NULL,
 * and so does an unknown _at: GREATEST skips NULLs, so without the CASE an
 * unknown block time would silently count as an update before the start, and
 * proposal_term_pay is STRICT so the NULL s reaches the result.
 */
CREATE OR REPLACE FUNCTION hafbe_backend.proposal_budget_after_update(
    _budget     NUMERIC,
    _start_date TIMESTAMP,
    _old_pay    BIGINT,
    _old_end    TIMESTAMP,
    _new_pay    BIGINT,
    _new_end    TIMESTAMP,
    _at         TIMESTAMP
)
RETURNS NUMERIC
LANGUAGE sql IMMUTABLE
AS $$
  SELECT ROUND(
    _budget
    - hafbe_backend.proposal_term_pay(_old_pay, s.at_, _old_end)
    + hafbe_backend.proposal_term_pay(_new_pay, s.at_, _new_end)
  )
  FROM (
    SELECT CASE WHEN _at IS NOT NULL THEN LEAST(GREATEST(_at, _start_date), _old_end) END AS at_
  ) s;
$$;

/*
 * The end date an update_proposal_operation sets, or NULL when it keeps the
 * current one. It comes through `extensions`:
 *   [ { "type": "update_proposal_end_date", "value": { "end_date": ... } } ]
 */
CREATE OR REPLACE FUNCTION hafbe_backend.proposal_update_end_date(_body JSONB)
RETURNS TIMESTAMP
LANGUAGE sql IMMUTABLE
AS $$
  SELECT (ext -> 'value' ->> 'end_date')::TIMESTAMP
  FROM jsonb_array_elements(COALESCE(_body -> 'extensions', '[]'::jsonb)) AS ext
  WHERE ext ->> 'type' = 'update_proposal_end_date'
  LIMIT 1;
$$;


/*
 * process_proposal_update_op: update_proposal_operation handler.
 *
 * JSON STRUCTURE (body_value):
 *   { "proposal_id": int, "creator": ..., "daily_pay": {"amount": ...},
 *     "subject": ..., "permlink": ..., "extensions": [...] }
 *
 * The optional new end_date is read by proposal_update_end_date(). total_budget
 * is adjusted at the op's block time, looked up from _id, so the signature (and
 * the dispatcher in process_proposals) stays as it was. The SET expressions see
 * the row's old daily_pay and end_date.
 */
CREATE OR REPLACE FUNCTION hafbe_backend.process_proposal_update_op(
    _body JSONB,
    _id   BIGINT
)
RETURNS VOID
LANGUAGE plpgsql VOLATILE
AS $$
DECLARE
  __proposal_id  INT       := (_body ->> 'proposal_id')::INT;
  __daily_pay    BIGINT    := (_body -> 'daily_pay' ->> 'amount')::BIGINT;
  __subject      TEXT      := _body ->> 'subject';
  __permlink     TEXT      := _body ->> 'permlink';
  __new_end_date TIMESTAMP := hafbe_backend.proposal_update_end_date(_body);
  __block_time   TIMESTAMP := (
    SELECT bv.created_at FROM hafbe_app.blocks_view bv
    WHERE bv.num = hafd.operation_id_to_block_num(_id)
  );
BEGIN
  UPDATE hafbe_app.current_proposals cp
  SET daily_pay    = __daily_pay,
      subject      = __subject,
      permlink     = __permlink,
      end_date     = COALESCE(__new_end_date, cp.end_date),
      total_budget = hafbe_backend.proposal_budget_after_update(
                       cp.total_budget, cp.start_date,
                       cp.daily_pay, cp.end_date,
                       __daily_pay, COALESCE(__new_end_date, cp.end_date),
                       __block_time),
      source_op    = _id
  WHERE cp.proposal_id = __proposal_id;
END
$$;


/*
 * process_proposal_remove_op: remove_proposal_operation handler.
 *
 * JSON STRUCTURE:
 *   { "proposal_owner": "alice", "proposal_ids": [1, 2, 3] }
 *
 * Marks each proposal as removed AND deletes its rows from
 * current_proposal_votes (hived drops the underlying proposal_vote_objects
 * when a proposal is removed). proposal_votes_history is preserved;
 * synthetic approve=FALSE rows are appended for the dropped votes.
 */
CREATE OR REPLACE FUNCTION hafbe_backend.process_proposal_remove_op(
    _body JSONB,
    _id   BIGINT
)
RETURNS VOID
LANGUAGE plpgsql VOLATILE
AS $$
BEGIN
  -- Write FALSE history rows while votes still exist, before deleting them.
  INSERT INTO hafbe_app.proposal_votes_history (proposal_id, voter_id, approve, source_op)
  SELECT cpv.proposal_id, cpv.voter_id, FALSE, _id
  FROM hafbe_app.current_proposal_votes cpv
  WHERE cpv.proposal_id = ANY(
    SELECT (pid)::INT FROM jsonb_array_elements_text(_body -> 'proposal_ids') AS pid
  );

  DELETE FROM hafbe_app.current_proposal_votes cpv
  WHERE cpv.proposal_id = ANY(
    SELECT (pid)::INT FROM jsonb_array_elements_text(_body -> 'proposal_ids') AS pid
  );

  -- Mark removed after vote cleanup. The proposal row stays for historical
  -- visibility, so ON DELETE CASCADE is only a defensive parent-delete guard.
  UPDATE hafbe_app.current_proposals cp
  SET removed   = TRUE,
      source_op = _id
  WHERE cp.proposal_id = ANY(
    SELECT (pid)::INT FROM jsonb_array_elements_text(_body -> 'proposal_ids') AS pid
  );
END
$$;


/*
 * process_proposal_pay_op: proposal_pay_operation handler (virtual op).
 *
 * JSON STRUCTURE:
 *   { "proposal_id": int, "receiver": ..., "payer": ...,
 *     "payment": { "amount": "...", "precision": 3, "nai": "@@..." } }
 *
 * DHF only pays in HBD precision-3, so amount is added as raw milli-HBD BIGINT.
 *
 * No replay guard: this runs in the same transaction as the context's
 * app_next_iteration, and on a fork HAF reverts current_proposals (a registered
 * table) to the fork point, so each payment is counted exactly once. A payment
 * naming a proposal without a current_proposals row is a no-op.
 */
CREATE OR REPLACE FUNCTION hafbe_backend.process_proposal_pay_op(
    _body JSONB,
    _id   BIGINT
)
RETURNS VOID
LANGUAGE plpgsql VOLATILE
AS $$
DECLARE
  __proposal_id INT    := (_body ->> 'proposal_id')::INT;
  __amount      BIGINT := (_body -> 'payment' ->> 'amount')::BIGINT;
BEGIN
  UPDATE hafbe_app.current_proposals cp
  SET paid_amount = cp.paid_amount + __amount
  WHERE cp.proposal_id = __proposal_id;
END
$$;


/*
 * process_proposal_vote_op: update_proposal_votes_operation handler.
 *
 * JSON STRUCTURE:
 *   { "voter": "alice", "proposal_ids": [1, 2], "approve": true/false, ... }
 *
 * Fans out proposal_ids, but ONLY over proposals that currently exist and are
 * not removed -- mirroring hived's update_proposal_votes_evaluator, which does
 * `continue` (silently skips) for any proposal_id that is missing or already
 * removed (see hive/libraries/chain/dhf_evaluator.cpp).
 *
 * Why this guard is required: pre-HF28 the chain ACCEPTED votes referencing a
 * nonexistent (not-yet-created or never-created) proposal and dropped them with
 * no effect -- no proposal_vote_object, nothing recorded. A real example in
 * full-replay history: block 52399763 has a vote approving proposal 168, which
 * was not created until block 52598127 (~200k blocks later). HF28
 * (HIVE_HARDFORK_1_28_DONT_TRY_VOTE_FOR_NONEXISTENT_PROPOSAL) turned this into a
 * hard rejection, so such ops only appear in pre-HF28 history. Without the
 * existence guard the FK current_proposal_votes -> current_proposals aborts the
 * INSERT and crashes block processing on that op.
 *
 * On approve=TRUE, upserts into current_proposal_votes; on approve=FALSE,
 * deletes from current_proposal_votes (inherently a no-op for the skipped
 * phantom/removed case, since no such row was ever inserted).
 */
CREATE OR REPLACE FUNCTION hafbe_backend.process_proposal_vote_op(
    _body JSONB,
    _id   BIGINT
)
RETURNS VOID
LANGUAGE plpgsql VOLATILE
AS $$
DECLARE
  __voter_id INT     := (SELECT av.id FROM hafbe_app.accounts_view av WHERE av.name = _body ->> 'voter');
  __approve  BOOLEAN := (_body ->> 'approve')::BOOLEAN;
BEGIN
  IF __voter_id IS NULL THEN
    RETURN;
  END IF;

  -- Step 1: append history rows, skipping proposals that hived itself skipped
  -- (missing or removed). Keeps history consistent with the actual on-chain
  -- effect and with the remove/expired handlers, which only log real votes.
  INSERT INTO hafbe_app.proposal_votes_history (proposal_id, voter_id, approve, source_op)
  SELECT (pid)::INT, __voter_id, __approve, _id
  FROM jsonb_array_elements_text(_body -> 'proposal_ids') AS pid
  WHERE EXISTS (
    SELECT 1 FROM hafbe_app.current_proposals cp
    WHERE cp.proposal_id = (pid)::INT AND NOT cp.removed
  );

  -- Step 2: update current state
  IF __approve THEN
    INSERT INTO hafbe_app.current_proposal_votes (voter_id, proposal_id, source_op)
    SELECT __voter_id, (pid)::INT, _id
    FROM jsonb_array_elements_text(_body -> 'proposal_ids') AS pid
    WHERE EXISTS (
      SELECT 1 FROM hafbe_app.current_proposals cp
      WHERE cp.proposal_id = (pid)::INT AND NOT cp.removed
    )
    ON CONFLICT ON CONSTRAINT pk_current_proposal_votes DO UPDATE SET
      source_op = EXCLUDED.source_op;
  ELSE
    DELETE FROM hafbe_app.current_proposal_votes cpv
    WHERE cpv.voter_id = __voter_id
      AND cpv.proposal_id IN (
        SELECT (pid)::INT
        FROM jsonb_array_elements_text(_body -> 'proposal_ids') AS pid
      );
  END IF;
END
$$;


/*
 * process_proposal_expired_account: declined_voting_rights or
 * expired_account_notification handler — proposal-side cleanup ONLY.
 *
 * (Witness-side cleanup is handled separately by hafbe_backend.process_expired_accounts.)
 *
 * Deletes all current proposal approvals for the account and writes
 * synthetic approve=FALSE rows to proposal_votes_history. Mirrors hived's
 * behavior of dropping a voter's proposal_vote_objects when they lose
 * voting rights.
 */
CREATE OR REPLACE FUNCTION hafbe_backend.process_proposal_expired_account(
    _body JSONB,
    _id   BIGINT
)
RETURNS VOID
LANGUAGE plpgsql VOLATILE
AS $$
DECLARE
  __account_id INT := (SELECT av.id FROM hafbe_app.accounts_view av WHERE av.name = _body ->> 'account');
BEGIN
  WITH deleted_proposal_votes AS (
    DELETE FROM hafbe_app.current_proposal_votes cpv
    WHERE cpv.voter_id = __account_id
    RETURNING cpv.voter_id, cpv.proposal_id
  )
  INSERT INTO hafbe_app.proposal_votes_history (proposal_id, voter_id, approve, source_op)
  SELECT dpv.proposal_id, dpv.voter_id, FALSE, _id
  FROM deleted_proposal_votes dpv;
END
$$;


RESET ROLE;
