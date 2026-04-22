SET ROLE hafbe_owner;

/*
 * process_proposal_votes: Processes update_proposal_votes operations.
 *
 * Core operation: update_proposal_votes_operation. Each op carries a voter,
 * an `approve` flag, and a `proposal_ids` array; it applies the same action
 * to every proposal id in that array.
 *
 * Updates tables:
 *   - hafbe_app.proposal_votes_history: complete (voter, proposal) change log
 *   - hafbe_app.current_proposal_votes: currently-active (approve=TRUE) votes
 *
 * WHY BATCH PROCESSING (not row-by-row):
 *   Unlike witness votes (where proxy ops cascade-delete votes and therefore
 *   require strict sequential processing), proposal votes have no inter-op
 *   dependencies - each op stands on its own. We still process in id order
 *   so that later ops override earlier ones correctly for the same
 *   (voter, proposal) pair via ON CONFLICT / DELETE, but we can express the
 *   whole block range as set-based SQL.
 *
 * NOTE on `proposal_ids`:
 *   `proposal_ids` is a JSON array of integers inside the op body;
 *   jsonb_array_elements_text expands it to one row per proposal id.
 */
CREATE OR REPLACE FUNCTION hafbe_app.process_proposal_votes(_from INT, _to INT)
RETURNS VOID
LANGUAGE 'plpgsql' VOLATILE
SET from_collapse_limit = 16
SET join_collapse_limit = 16
SET jit = OFF
AS $$
DECLARE
  _op_update_proposal_votes INT := (SELECT id FROM hafd.operation_types WHERE name = 'hive::protocol::update_proposal_votes_operation');
  _result INT;
BEGIN

  /*
   * Expand each op into one row per (voter, proposal_id) and persist.
   *
   * The CTE fans out `proposal_ids` via jsonb_array_elements_text, resolves
   * the voter account name to an id, and keeps the source operation id so
   * timestamps/ordering can be recovered later via hafd.operation_id_to_block_num.
   */
  WITH expanded AS MATERIALIZED (
    SELECT
      (pid)::INT                                   AS proposal_id,
      (SELECT av.id FROM hafbe_app.accounts_view av
       WHERE av.name = ov.body_value ->> 'voter')  AS voter_id,
      (ov.body_value ->> 'approve')::BOOLEAN       AS approve,
      ov.id                                        AS source_op
    FROM hafbe_app.operations_view ov
    CROSS JOIN LATERAL jsonb_array_elements_text(ov.body_value -> 'proposal_ids') AS pid
    WHERE ov.op_type_id = _op_update_proposal_votes
      AND ov.block_num BETWEEN _from AND _to
      AND ov.id >= hafd.operation_id(_from, 0)
      AND ov.id < hafd.operation_id(_to + 1, 0)
  ),

  /*
   * History: append every (voter, proposal, approve) change.
   */
  history_insert AS (
    INSERT INTO hafbe_app.proposal_votes_history (proposal_id, voter_id, approve, source_op)
    SELECT e.proposal_id, e.voter_id, e.approve, e.source_op
    FROM expanded e
    WHERE e.voter_id IS NOT NULL
    RETURNING 1
  ),

  /*
   * Current state: upsert approvals.
   *
   * Ordered by source_op so that when the same (voter, proposal) is touched
   * multiple times within the range, the latest approve=TRUE wins the upsert.
   * DISTINCT ON picks the final event per pair; the DELETE below removes
   * pairs whose last event in the range is approve=FALSE.
   */
  approvals AS (
    SELECT DISTINCT ON (e.voter_id, e.proposal_id)
      e.voter_id, e.proposal_id, e.approve, e.source_op
    FROM expanded e
    WHERE e.voter_id IS NOT NULL
    ORDER BY e.voter_id, e.proposal_id, e.source_op DESC
  ),
  upsert_current AS (
    INSERT INTO hafbe_app.current_proposal_votes (voter_id, proposal_id, source_op)
    SELECT a.voter_id, a.proposal_id, a.source_op
    FROM approvals a
    WHERE a.approve
    ON CONFLICT ON CONSTRAINT pk_current_proposal_votes DO UPDATE SET
      source_op = EXCLUDED.source_op
    RETURNING 1
  ),
  removals AS (
    DELETE FROM hafbe_app.current_proposal_votes cpv
    USING approvals a
    WHERE a.voter_id = cpv.voter_id
      AND a.proposal_id = cpv.proposal_id
      AND NOT a.approve
    RETURNING 1
  )
  SELECT
    (SELECT COUNT(*) FROM history_insert) +
    (SELECT COUNT(*) FROM upsert_current) +
    (SELECT COUNT(*) FROM removals)
  INTO _result;

END
$$;

RESET ROLE;
