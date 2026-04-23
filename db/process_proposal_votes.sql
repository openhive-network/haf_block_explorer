SET ROLE hafbe_owner;

/*
 * process_proposal_votes: Processes update_proposal_votes operations.
 *
 * Core operation: update_proposal_votes_operation. Each op carries a voter,
 * an `approve` flag, and a `proposal_ids` array; it applies the same action
 * to every proposal id in that array.
 *
 * Updates table:
 *   - hafbe_app.proposal_votes_history: complete (voter, proposal) change log
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
BEGIN

  /*
   * Expand each op into one row per (voter, proposal_id) and append to history.
   *
   * The CTE fans out `proposal_ids` via jsonb_array_elements_text and resolves
   * the voter account name to an id. source_op lets us recover block/timestamp
   * later via hafd.operation_id_to_block_num.
   */
  WITH expanded AS (
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
  )
  INSERT INTO hafbe_app.proposal_votes_history (proposal_id, voter_id, approve, source_op)
  SELECT e.proposal_id, e.voter_id, e.approve, e.source_op
  FROM expanded e
  WHERE e.voter_id IS NOT NULL;

END
$$;

RESET ROLE;
