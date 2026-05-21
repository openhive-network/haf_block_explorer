SET ROLE hafbe_owner;

/*
 * process_proposals: Unified processor for ALL proposal-related operations.
 *
 * Mirrors process_witness_votes' design (row-by-row in operation_id order)
 * so that cascading effects across ops in the same block range work
 * correctly even during MASSIVE sync.
 *
 * STEP A (batch pre-pass)
 *   Pair create_proposal_operation with the virtual proposal_fee_operation
 *   to capture the assigned proposal_id, then INSERT into current_proposals.
 *   Creates have no interaction with current_proposal_votes, so batching is
 *   safe and avoids the awkwardness of looking up the matching create from
 *   inside a per-row fee handler.
 *
 * STEP B (row-by-row dispatch)
 *   All remaining proposal-touching ops are processed sequentially in
 *   operation_id order:
 *
 *     update_proposal_operation        -> process_proposal_update_op
 *     remove_proposal_operation        -> process_proposal_remove_op
 *     proposal_pay_operation           -> process_proposal_pay_op
 *     update_proposal_votes_operation  -> process_proposal_vote_op
 *     declined_voting_rights_operation OR
 *     expired_account_notification_op  -> process_proposal_expired_account
 *
 *   This is critical for fresh-sync correctness. Example sequence within a
 *   MASSIVE batch range:
 *
 *     op 100: alice approves proposal X
 *     op 200: alice loses voting rights
 *     op 300: someone removes proposal X
 *
 *   With row-by-row processing in id order: op 100 inserts the row, op 200
 *   deletes it (writing approve=FALSE history), op 300 finds no row to
 *   delete (correct), and marks X removed. Final state matches hived.
 *
 * NOTE: declined_voting_rights / expired_account_notification are ALSO
 *   pulled by process_witness_votes for witness-state cleanup. Each
 *   processor maintains its own state; both pulls are independent and
 *   leave the other's state untouched.
 *
 * WHY FOR LOOP rather than the CTE+CASE+ORDER BY pattern in process_witness_votes:
 *   The CTE+CASE pattern (see db/process_witness_votes.sql:74-126) relies on
 *   the planner executing the CASE expressions in ORDER BY id sequence. PostgreSQL
 *   does not formally guarantee that side-effecting functions in a SELECT list
 *   fire in ORDER BY order — it works in practice today but is a planner
 *   assumption, not a spec guarantee. For proposal processing the ordering
 *   invariant is safety-critical (a remove-then-vote sequence in the same
 *   batch must not insert a vote after the cascade), so we use an explicit
 *   FOR loop whose iteration order is guaranteed by SQL semantics.
 */
CREATE OR REPLACE FUNCTION hafbe_app.process_proposals(_from INT, _to INT)
RETURNS VOID
LANGUAGE 'plpgsql' VOLATILE
SET from_collapse_limit = 16
SET join_collapse_limit = 16
SET jit = OFF
AS $$
DECLARE
  _op_create_proposal              INT := (SELECT id FROM hafd.operation_types WHERE name = 'hive::protocol::create_proposal_operation');
  _op_proposal_fee                 INT := (SELECT id FROM hafd.operation_types WHERE name = 'hive::protocol::proposal_fee_operation');
  _op_update_proposal              INT := (SELECT id FROM hafd.operation_types WHERE name = 'hive::protocol::update_proposal_operation');
  _op_remove_proposal              INT := (SELECT id FROM hafd.operation_types WHERE name = 'hive::protocol::remove_proposal_operation');
  _op_proposal_pay                 INT := (SELECT id FROM hafd.operation_types WHERE name = 'hive::protocol::proposal_pay_operation');
  _op_update_proposal_votes        INT := (SELECT id FROM hafd.operation_types WHERE name = 'hive::protocol::update_proposal_votes_operation');
  _op_declined_voting_rights       INT := hafbe_backend.op_declined_voting_rights();
  _op_expired_account_notification INT := hafbe_backend.op_expired_account_notification();
  _op                              RECORD;
BEGIN

  -- ============================================================================
  -- STEP A: batch-pair create_proposal_operation with proposal_fee_operation
  -- to capture proposal_id, then INSERT into current_proposals.
  --
  -- Pairing key: (block_num, creator, rank-by-id). The Nth create by a creator
  -- in a block pairs with the Nth fee from that creator in the same block.
  -- We deliberately do NOT include trx_in_block in the partition because
  -- HAF's trx_in_block convention for virtual ops is not portable: in some
  -- HAF versions virtual ops inherit the triggering tx's trx_in_block, in
  -- others they get -1. Pairing by (block, creator, id-rank) is robust to
  -- either convention, since hived emits the fee virtual op immediately
  -- after the create succeeds (so id ordering matches creation ordering).
  -- ============================================================================
  WITH create_ops AS (
    SELECT
      ov.id                                              AS source_op,
      ov.block_num,
      ov.body_value ->> 'creator'                        AS creator_name,
      ov.body_value ->> 'receiver'                       AS receiver_name,
      (ov.body_value ->> 'start_date')::TIMESTAMP       AS start_date,
      (ov.body_value ->> 'end_date')::TIMESTAMP         AS end_date,
      (ov.body_value -> 'daily_pay' ->> 'amount')::BIGINT AS daily_pay,
      ov.body_value ->> 'subject'                        AS subject,
      ov.body_value ->> 'permlink'                       AS permlink,
      ROW_NUMBER() OVER (
        PARTITION BY ov.block_num, ov.body_value ->> 'creator'
        ORDER BY ov.id
      ) AS rk
    FROM hafbe_app.operations_view ov
    WHERE ov.op_type_id = _op_create_proposal
      AND ov.block_num BETWEEN _from AND _to
      AND ov.id >= hafd.operation_id(_from, 0)
      AND ov.id < hafd.operation_id(_to + 1, 0)
  ),
  fee_ops AS (
    SELECT
      ov.block_num,
      ov.body_value ->> 'creator'              AS creator_name,
      (ov.body_value ->> 'proposal_id')::INT  AS proposal_id,
      ROW_NUMBER() OVER (
        PARTITION BY ov.block_num, ov.body_value ->> 'creator'
        ORDER BY ov.id
      ) AS rk
    FROM hafbe_app.operations_view ov
    WHERE ov.op_type_id = _op_proposal_fee
      AND ov.block_num BETWEEN _from AND _to
      AND ov.id >= hafd.operation_id(_from, 0)
      AND ov.id < hafd.operation_id(_to + 1, 0)
  ),
  paired AS (
    SELECT
      f.proposal_id,
      (SELECT av.id FROM hafbe_app.accounts_view av WHERE av.name = c.creator_name)  AS creator_id,
      (SELECT av.id FROM hafbe_app.accounts_view av WHERE av.name = c.receiver_name) AS receiver_id,
      c.start_date,
      c.end_date,
      c.daily_pay,
      c.subject,
      c.permlink,
      c.source_op
    FROM create_ops c
    JOIN fee_ops f
      ON f.block_num    = c.block_num
     AND f.creator_name = c.creator_name
     AND f.rk           = c.rk
  )
  INSERT INTO hafbe_app.current_proposals
    (proposal_id, creator_id, receiver_id, start_date, end_date, daily_pay, subject, permlink, removed, source_op)
  SELECT p.proposal_id, p.creator_id, p.receiver_id, p.start_date, p.end_date,
         p.daily_pay, p.subject, p.permlink, FALSE, p.source_op
  FROM paired p
  ON CONFLICT ON CONSTRAINT pk_current_proposals DO NOTHING;

  -- ============================================================================
  -- STEP B: row-by-row dispatch over the remaining proposal-touching ops,
  -- in operation_id order. CRITICAL for correctness during MASSIVE sync.
  -- ============================================================================
  FOR _op IN
    SELECT
      ov.body_value AS body,
      ov.id         AS id,
      ov.op_type_id AS op_type
    FROM hafbe_app.operations_view ov
    WHERE ov.op_type_id IN (
        _op_update_proposal,
        _op_remove_proposal,
        _op_proposal_pay,
        _op_update_proposal_votes,
        _op_declined_voting_rights,
        _op_expired_account_notification
      )
      AND ov.block_num BETWEEN _from AND _to
      AND ov.id >= hafd.operation_id(_from, 0)
      AND ov.id < hafd.operation_id(_to + 1, 0)
    ORDER BY ov.id
  LOOP
    CASE
      WHEN _op.op_type = _op_update_proposal THEN
        PERFORM hafbe_backend.process_proposal_update_op(_op.body, _op.id);
      WHEN _op.op_type = _op_remove_proposal THEN
        PERFORM hafbe_backend.process_proposal_remove_op(_op.body, _op.id);
      WHEN _op.op_type = _op_proposal_pay THEN
        PERFORM hafbe_backend.process_proposal_pay_op(_op.body, _op.id);
      WHEN _op.op_type = _op_update_proposal_votes THEN
        PERFORM hafbe_backend.process_proposal_vote_op(_op.body, _op.id);
      WHEN _op.op_type = _op_declined_voting_rights
        OR _op.op_type = _op_expired_account_notification THEN
        PERFORM hafbe_backend.process_proposal_expired_account(_op.body, _op.id);
      ELSE
        NULL;
    END CASE;
  END LOOP;

END
$$;

RESET ROLE;
