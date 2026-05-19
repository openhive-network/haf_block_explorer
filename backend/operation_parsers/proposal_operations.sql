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
 *   - hafbe_app.proposal_payments      (per-payment ledger)
 */


/*
 * process_proposal_update_op: update_proposal_operation handler.
 *
 * JSON STRUCTURE (body_value):
 *   { "proposal_id": int, "creator": ..., "daily_pay": {"amount": ...},
 *     "subject": ..., "permlink": ..., "extensions": [...] }
 *
 * Optional end_date comes through `extensions`:
 *   [ { "type": "update_proposal_end_date", "value": { "end_date": ... } } ]
 */
CREATE OR REPLACE FUNCTION hafbe_backend.process_proposal_update_op(
    _body JSONB,
    _id   BIGINT
)
RETURNS VOID
LANGUAGE 'plpgsql' VOLATILE
AS $$
DECLARE
  __proposal_id  INT       := (_body ->> 'proposal_id')::INT;
  __daily_pay    BIGINT    := (_body -> 'daily_pay' ->> 'amount')::BIGINT;
  __subject      TEXT      := _body ->> 'subject';
  __permlink     TEXT      := _body ->> 'permlink';
  __new_end_date TIMESTAMP := (
    SELECT (ext -> 'value' ->> 'end_date')::TIMESTAMP
    FROM jsonb_array_elements(COALESCE(_body -> 'extensions', '[]'::jsonb)) AS ext
    WHERE ext ->> 'type' = 'update_proposal_end_date'
    LIMIT 1
  );
BEGIN
  UPDATE hafbe_app.current_proposals cp
  SET daily_pay = __daily_pay,
      subject   = __subject,
      permlink  = __permlink,
      end_date  = COALESCE(__new_end_date, cp.end_date),
      source_op = _id
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
LANGUAGE 'plpgsql' VOLATILE
AS $$
BEGIN
  WITH ids AS (
    SELECT (pid)::INT AS proposal_id
    FROM jsonb_array_elements_text(_body -> 'proposal_ids') AS pid
  ),
  mark_removed AS (
    UPDATE hafbe_app.current_proposals cp
    SET removed   = TRUE,
        source_op = _id
    FROM ids
    WHERE cp.proposal_id = ids.proposal_id
    RETURNING cp.proposal_id
  ),
  drop_active_votes AS (
    DELETE FROM hafbe_app.current_proposal_votes cpv
    USING ids
    WHERE cpv.proposal_id = ids.proposal_id
    RETURNING cpv.voter_id, cpv.proposal_id
  )
  INSERT INTO hafbe_app.proposal_votes_history (proposal_id, voter_id, approve, source_op)
  SELECT dav.proposal_id, dav.voter_id, FALSE, _id
  FROM drop_active_votes dav;
END
$$;


/*
 * process_proposal_pay_op: proposal_pay_operation handler (virtual op).
 *
 * JSON STRUCTURE:
 *   { "proposal_id": int, "receiver": ..., "payer": ...,
 *     "payment": { "amount": "...", "precision": 3, "nai": "@@..." } }
 *
 * DHF only pays in HBD precision-3, so amount stored as raw milli-HBD BIGINT.
 */
CREATE OR REPLACE FUNCTION hafbe_backend.process_proposal_pay_op(
    _body JSONB,
    _id   BIGINT
)
RETURNS VOID
LANGUAGE 'plpgsql' VOLATILE
AS $$
BEGIN
  INSERT INTO hafbe_app.proposal_payments (proposal_id, amount, source_op)
  VALUES (
    (_body ->> 'proposal_id')::INT,
    (_body -> 'payment' ->> 'amount')::BIGINT,
    _id
  )
  ON CONFLICT ON CONSTRAINT pk_proposal_payments DO NOTHING;
END
$$;


/*
 * process_proposal_vote_op: update_proposal_votes_operation handler.
 *
 * JSON STRUCTURE:
 *   { "voter": "alice", "proposal_ids": [1, 2], "approve": true/false, ... }
 *
 * Fans out proposal_ids: one history row per (voter, proposal) per op.
 * On approve=TRUE, upserts into current_proposal_votes; on approve=FALSE,
 * deletes from current_proposal_votes.
 */
CREATE OR REPLACE FUNCTION hafbe_backend.process_proposal_vote_op(
    _body JSONB,
    _id   BIGINT
)
RETURNS VOID
LANGUAGE 'plpgsql' VOLATILE
AS $$
DECLARE
  __voter_id INT     := (SELECT av.id FROM hafbe_app.accounts_view av WHERE av.name = _body ->> 'voter');
  __approve  BOOLEAN := (_body ->> 'approve')::BOOLEAN;
BEGIN
  IF __voter_id IS NULL THEN
    RETURN;
  END IF;

  -- Step 1: append history rows for each (voter, proposal) in the array
  INSERT INTO hafbe_app.proposal_votes_history (proposal_id, voter_id, approve, source_op)
  SELECT (pid)::INT, __voter_id, __approve, _id
  FROM jsonb_array_elements_text(_body -> 'proposal_ids') AS pid;

  -- Step 2: update current state
  IF __approve THEN
    INSERT INTO hafbe_app.current_proposal_votes (voter_id, proposal_id, source_op)
    SELECT __voter_id, (pid)::INT, _id
    FROM jsonb_array_elements_text(_body -> 'proposal_ids') AS pid
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
LANGUAGE 'plpgsql' VOLATILE
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
