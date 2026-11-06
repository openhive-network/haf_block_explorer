-- The incremental witness vote cache refresh against the full recompute.
--
-- hafbe_app.process_witness_votes_cache(_block) updates the caches from the accounts
-- the block's operations impact, and recomputes them in full for the cases that
-- cannot be derived that way. This drives it through each case and, after every
-- refresh, compares all four witness caches and proposal_vote_stats_cache row for row
-- against a full recompute (process_witness_votes_cache() and
-- process_proposal_vote_stats_cache()):
--   - an ordinary block naming a proxy setter whose proxy votes, whose balance grows
--     enough to reorder the witness ranks: the proxy's proxied vests move with it.
--     Must take the incremental path;
--   - a fork: the caches hold a block whose balance change was reverted, and the next
--     block handed over is at or below it and does not name the account;
--   - a restart gap: balances moved in blocks no refresh saw;
--   - a voter's only proposal vote deleted, as remove_proposal does, in a block with
--     an operation that forces the full recompute;
--   - a new witness registered for an account the block names;
--   - the daily-change window moved since the last refresh: the state row carries a
--     stale window and a cache row only the full recompute repairs is altered;
--   - a block whose routed fill_vesting_withdraw is the only operation naming a
--     tracked account whose vests it moves, and that names no account proxying to
--     it. Must take the incremental path.
-- For the fallback cases it also checks that the incremental path alone would have
-- left the caches wrong, so a fallback that stopped firing fails the test.
--
-- The daily-change cache (witness_votes_change_cache) is filled from today's vote
-- events, which a synced chain whose blocks all predate today does not have: when it
-- is empty, a vote event of the proxy above is added to the window so that cache is
-- compared non-empty. The output says which.
--
-- The blocks are real (the synced chain's own operations decide which accounts each
-- block names); their effects on balances and hafbe's tables are simulated by writing
-- those tables directly. A fork is simulated by reverting such a write. When the role
-- may write hafd.operations (haf_admin), the remove_proposal case also adds a real
-- remove_proposal operation to a block; otherwise it says it skipped that part.
-- Needs a synced hafbe with its caches filled and the balance tracker's schema first
-- on the search path. Everything is rolled back.

BEGIN;

CREATE TEMP TABLE before_avs AS TABLE hafbe_app.account_vest_stats_cache WITH NO DATA;
CREATE TEMP TABLE before_wv AS TABLE hafbe_app.witness_votes_cache WITH NO DATA;
CREATE TEMP TABLE before_wr AS TABLE hafbe_app.witness_rank_cache WITH NO DATA;
CREATE TEMP TABLE before_wc AS TABLE hafbe_app.witness_votes_change_cache WITH NO DATA;
CREATE TEMP TABLE before_pv AS TABLE hafbe_app.proposal_vote_stats_cache WITH NO DATA;

-- What single_processing() does with the caches for _block.
CREATE FUNCTION pg_temp.refresh(_block INT)
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM hafbe_app.process_witness_votes_cache(_block);
  PERFORM hafbe_app.process_proposal_vote_stats_cache();
END
$$;

-- The caches as the last refresh left them against a full recompute: per cache, the
-- number of rows only one of the two has. NULL when they are identical. Leaves the
-- caches recomputed in full.
CREATE FUNCTION pg_temp.differences_from_full()
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
  _diff TEXT;
BEGIN
  TRUNCATE before_avs, before_wv, before_wr, before_wc, before_pv;
  INSERT INTO before_avs TABLE hafbe_app.account_vest_stats_cache;
  INSERT INTO before_wv TABLE hafbe_app.witness_votes_cache;
  INSERT INTO before_wr TABLE hafbe_app.witness_rank_cache;
  INSERT INTO before_wc TABLE hafbe_app.witness_votes_change_cache;
  INSERT INTO before_pv TABLE hafbe_app.proposal_vote_stats_cache;

  PERFORM hafbe_app.process_witness_votes_cache();
  PERFORM hafbe_app.process_proposal_vote_stats_cache();

  SELECT string_agg(format('%s: %s rows', d.cache, d.n), ', ')
  INTO _diff
  FROM (
    SELECT 'account_vest_stats_cache' AS cache, count(*) AS n
    FROM ((TABLE before_avs EXCEPT TABLE hafbe_app.account_vest_stats_cache)
          UNION ALL (TABLE hafbe_app.account_vest_stats_cache EXCEPT TABLE before_avs)) x
    UNION ALL
    SELECT 'witness_votes_cache', count(*)
    FROM ((TABLE before_wv EXCEPT TABLE hafbe_app.witness_votes_cache)
          UNION ALL (TABLE hafbe_app.witness_votes_cache EXCEPT TABLE before_wv)) x
    UNION ALL
    SELECT 'witness_rank_cache', count(*)
    FROM ((TABLE before_wr EXCEPT TABLE hafbe_app.witness_rank_cache)
          UNION ALL (TABLE hafbe_app.witness_rank_cache EXCEPT TABLE before_wr)) x
    UNION ALL
    SELECT 'witness_votes_change_cache', count(*)
    FROM ((TABLE before_wc EXCEPT TABLE hafbe_app.witness_votes_change_cache)
          UNION ALL (TABLE hafbe_app.witness_votes_change_cache EXCEPT TABLE before_wc)) x
    UNION ALL
    SELECT 'proposal_vote_stats_cache', count(*)
    FROM ((TABLE before_pv EXCEPT TABLE hafbe_app.proposal_vote_stats_cache)
          UNION ALL (TABLE hafbe_app.proposal_vote_stats_cache EXCEPT TABLE before_pv)) x
  ) d
  WHERE d.n > 0;

  RETURN _diff;
END
$$;

CREATE FUNCTION pg_temp.expect_match(_case TEXT)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
  _diff TEXT := pg_temp.differences_from_full();
BEGIN
  IF _diff IS NOT NULL THEN
    RAISE EXCEPTION '%: the caches differ from a full recompute in %', _case, _diff;
  END IF;
  RAISE NOTICE '%: every cache matches a full recompute', _case;
END
$$;

-- The negative control of a fallback case: refreshing _block as the direct successor
-- of the last refreshed block, with none of the operations that force the full
-- recompute, must leave the caches wrong. Runs in a subtransaction it rolls back.
CREATE FUNCTION pg_temp.expect_incremental_misses(_case TEXT, _block INT)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
  _diff TEXT;
BEGIN
  BEGIN
    PERFORM pg_temp.set_last(_block - 1);
    PERFORM pg_temp.refresh(_block);
    _diff := pg_temp.differences_from_full();
    RAISE EXCEPTION USING ERRCODE = 'P0099', MESSAGE = COALESCE(_diff, '');
  EXCEPTION WHEN SQLSTATE 'P0099' THEN
    GET STACKED DIAGNOSTICS _diff = MESSAGE_TEXT;
  END;
  IF _diff = '' THEN
    RAISE EXCEPTION '%: the incremental path alone already matches a full recompute, so the case tests nothing', _case;
  END IF;
  RAISE NOTICE '%: the incremental path alone would differ in %', _case, _diff;
END
$$;

-- Record _block as the last block the caches were refreshed for, with _first_block_num
-- as the window they were refreshed with.
CREATE FUNCTION pg_temp.set_state(_block INT, _first_block_num INT)
RETURNS VOID
LANGUAGE sql
AS $$
  INSERT INTO hafbe_app.witness_votes_cache_state (singleton, block_num, first_block_num)
  VALUES (TRUE, _block, _first_block_num)
  ON CONFLICT (singleton) DO UPDATE SET
    block_num = EXCLUDED.block_num, first_block_num = EXCLUDED.first_block_num;
$$;

-- Record _block as the last block the caches were refreshed for, as its refresh would.
CREATE FUNCTION pg_temp.set_last(_block INT)
RETURNS VOID
LANGUAGE sql
AS $$
  SELECT pg_temp.set_state(_block, hafbe_app.witness_votes_cache_window_start());
$$;

-- Refresh _block and say whether that recomputed the caches in full: only the full
-- recompute repairs a cache row of _canary, a tracked account _block cannot change,
-- altered first. The row is restored when the refresh left it altered.
CREATE FUNCTION pg_temp.refresh_took_full(_block INT, _canary INT)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
DECLARE
  _vests BIGINT;
BEGIN
  UPDATE hafbe_app.account_vest_stats_cache SET vests = vests + 1 WHERE account_id = _canary
  RETURNING vests INTO _vests;
  PERFORM pg_temp.refresh(_block);
  IF (SELECT vests FROM hafbe_app.account_vest_stats_cache WHERE account_id = _canary) = _vests THEN
    UPDATE hafbe_app.account_vest_stats_cache SET vests = vests - 1 WHERE account_id = _canary;
    RETURN FALSE;
  END IF;
  RETURN TRUE;
END
$$;

-- Append an operation to _block, after its last one. The position comes from
-- the ids, not op_pos: op_pos need not match the position an id encodes.
CREATE FUNCTION pg_temp.add_op(_block INT, _op_name TEXT, _body JSONB)
RETURNS BIGINT
LANGUAGE sql
AS $$
  INSERT INTO hafd.operations (id, trx_in_block, op_pos, op_type_id, body_value)
  SELECT
    hafd.operation_id(_block, p.pos),
    0,
    p.pos,
    (SELECT ot.id FROM hafd.operation_types ot WHERE ot.name = _op_name),
    _body
  FROM (
    SELECT (COALESCE(max(o.id) - hafd.operation_id(_block, 0), -1) + 1)::INT AS pos
    FROM hafd.operations o
    WHERE o.id >= hafd.operation_id(_block, 0) AND o.id < hafd.operation_id(_block + 1, 0)
  ) p
  RETURNING id;
$$;

-- The accounts _block's operations impact, as the refresh derives them.
CREATE FUNCTION pg_temp.named(_block INT)
RETURNS INT[]
LANGUAGE sql
AS $$
  SELECT COALESCE(array_agg(DISTINCT av.id), '{}')
  FROM hafbe_app.operations_view ov
  CROSS JOIN hive.get_impacted_accounts(ov.body::hafd.operation) AS ia (name)
  JOIN hafbe_app.accounts_view av ON av.name = ia.name
  WHERE ov.block_num = _block
    AND ov.id >= hafd.operation_id(_block, 0) AND ov.id < hafd.operation_id(_block + 1, 0);
$$;

-- Whether _block has an operation that forces the full recompute.
CREATE FUNCTION pg_temp.has_full_op(_block INT)
RETURNS BOOLEAN
LANGUAGE sql
AS $$
  SELECT EXISTS (
    SELECT 1 FROM hafbe_app.operations_view ov
    WHERE ov.op_type_id = ANY(hafbe_app.witness_votes_cache_full_op_types())
      AND ov.block_num = _block
      AND ov.id >= hafd.operation_id(_block, 0) AND ov.id < hafd.operation_id(_block + 1, 0)
  );
$$;

-- How many of _block's operations impact the account _name.
CREATE FUNCTION pg_temp.times_named(_block INT, _name TEXT)
RETURNS BIGINT
LANGUAGE sql
AS $$
  SELECT count(*)
  FROM hafbe_app.operations_view ov
  CROSS JOIN hive.get_impacted_accounts(ov.body::hafd.operation) AS ia (name)
  WHERE ov.block_num = _block
    AND ov.id >= hafd.operation_id(_block, 0) AND ov.id < hafd.operation_id(_block + 1, 0)
    AND ia.name = _name;
$$;

-- An account and the (up to 4) proxies above it.
CREATE FUNCTION pg_temp.with_proxies(_account INT)
RETURNS INT[]
LANGUAGE sql
AS $$
  SELECT array_remove(ARRAY[_account, p1.proxy_id, p2.proxy_id, p3.proxy_id, p4.proxy_id], NULL)
  FROM (SELECT _account AS account_id) a
  LEFT JOIN hafbe_app.current_account_proxies p1 ON p1.account_id = a.account_id
  LEFT JOIN hafbe_app.current_account_proxies p2 ON p2.account_id = p1.proxy_id
  LEFT JOIN hafbe_app.current_account_proxies p3 ON p3.account_id = p2.proxy_id
  LEFT JOIN hafbe_app.current_account_proxies p4 ON p4.account_id = p3.proxy_id;
$$;

CREATE FUNCTION pg_temp.add_vests(_account INT, _vests BIGINT)
RETURNS VOID
LANGUAGE sql
AS $$
  UPDATE current_account_balances
  SET balance = balance + _vests
  WHERE account = _account AND nai = btracker_backend.nai_vests();
$$;

DO $$
DECLARE
  _head       INT := (SELECT c.current_block_num FROM hafd.contexts c WHERE c.name = 'hafbe_app');
  _window     INT := hafbe_app.witness_votes_cache_window_start();
  _bump       BIGINT := (SELECT max(votes) FROM hafbe_app.witness_votes_cache);
  _block      INT;    -- names _setter, no operation forcing the full recompute
  _named      INT[];  -- the accounts _block names
  _setter     INT;    -- proxies to _proxy
  _proxy      INT;    -- votes for witnesses
  _chain      INT[];  -- _setter and the proxies above it
  _other      INT;    -- below _block, names nothing of _chain, no operation forcing the full recompute
  _other_named INT[];
  _full_block INT;    -- has an operation forcing the full recompute
  _witness    INT;    -- named by _other but not by _block, not a witness
  _voter      INT;    -- no vote, proxy or proposal vote, not a witness, not named by _block
  _canary     INT;
  _changes    BIGINT; -- witness_votes_change_cache rows
  _wd_block   INT;    -- a routed fill_vesting_withdraw is the only operation naming _wd_to
  _wd_from    INT;
  _wd_to      INT;    -- tracked, receives the withdrawal as vests
  _wd_vests   BIGINT; -- the vests _wd_to receives
  _to_v       BIGINT;
  _candidate  RECORD;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM hafbe_app.witness_rank_cache) THEN
    RAISE EXCEPTION 'the witness caches are empty: run hafbe_app.process_witness_votes_cache() after the sync';
  END IF;
  IF cardinality(hafbe_app.witness_votes_cache_full_op_types()) <> 7 THEN
    RAISE EXCEPTION 'witness_votes_cache_full_op_types() resolves % of its 7 operation names',
      cardinality(hafbe_app.witness_votes_cache_full_op_types());
  END IF;

  -- The newest block naming a proxy setter whose proxy votes and has a balance.
  FOR _candidate IN
    SELECT cap.account_id, cap.proxy_id, ao.block_num
    FROM hafbe_app.current_account_proxies cap
    CROSS JOIN LATERAL (
      SELECT aov.block_num
      FROM hive.account_operations_view aov
      WHERE aov.account_id = cap.account_id AND aov.block_num <= _head
      ORDER BY aov.account_op_seq_no DESC
      LIMIT 5
    ) ao
    WHERE EXISTS (SELECT 1 FROM hafbe_app.current_witness_votes cwv WHERE cwv.voter_id = cap.proxy_id)
      AND EXISTS (SELECT 1 FROM current_account_balances cab WHERE cab.account = cap.account_id AND cab.nai = btracker_backend.nai_vests())
    ORDER BY ao.block_num DESC, cap.account_id
  LOOP
    IF NOT pg_temp.has_full_op(_candidate.block_num)
       AND _candidate.account_id = ANY(pg_temp.named(_candidate.block_num)) THEN
      _setter := _candidate.account_id;
      _proxy  := _candidate.proxy_id;
      _block  := _candidate.block_num;
      EXIT;
    END IF;
  END LOOP;
  IF _block IS NULL THEN
    RAISE EXCEPTION 'the synced data has no block naming a proxy setter whose proxy votes';
  END IF;
  _named := pg_temp.named(_block);
  _chain := pg_temp.with_proxies(_setter);

  _changes := (SELECT count(*) FROM hafbe_app.witness_votes_change_cache);
  IF _changes = 0 THEN
    -- A vote of _proxy's own today: the ordinary block's balance change, which moves
    -- _proxy's vests, then moves this cache too.
    INSERT INTO hafbe_app.witness_votes_history (witness_id, voter_id, approve, source_op)
    SELECT cwv.witness_id, cwv.voter_id, TRUE, hafd.operation_id(_window, 0)
    FROM hafbe_app.current_witness_votes cwv
    WHERE cwv.voter_id = _proxy
    ORDER BY cwv.witness_id
    LIMIT 1;
    PERFORM hafbe_app.process_witness_votes_cache();
    RAISE NOTICE 'witness_votes_change_cache: the synced data has no vote event in the window from block %; added one of proxy %, now % rows',
      _window, _proxy, (SELECT count(*) FROM hafbe_app.witness_votes_change_cache);
  ELSE
    RAISE NOTICE 'witness_votes_change_cache: % rows from the synced data (window from block %)', _changes, _window;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM hafbe_app.witness_votes_change_cache) THEN
    RAISE EXCEPTION 'witness_votes_change_cache is empty, so its comparison tests nothing';
  END IF;

  SELECT b.num INTO _other
  FROM generate_series(_block - 1, GREATEST(_block - 500, 2), -1) AS b (num)
  WHERE NOT pg_temp.has_full_op(b.num)
    AND NOT pg_temp.named(b.num) && _chain
  LIMIT 1;
  _other_named := pg_temp.named(_other);

  SELECT b.num INTO _full_block
  FROM generate_series(_head, GREATEST(_head - 20000, 2), -1) AS b (num)
  WHERE pg_temp.has_full_op(b.num)
  LIMIT 1;

  SELECT n.account_id INTO _witness
  FROM unnest(_other_named) AS n (account_id)
  WHERE NOT n.account_id = ANY(_named)
    AND NOT EXISTS (SELECT 1 FROM hafbe_app.current_witnesses cw WHERE cw.witness_id = n.account_id)
  ORDER BY n.account_id
  LIMIT 1;

  SELECT cab.account INTO _voter
  FROM current_account_balances cab
  WHERE cab.nai = btracker_backend.nai_vests()
    AND cab.balance > 0
    AND cab.account IS DISTINCT FROM _witness
    AND NOT cab.account = ANY(_named)
    AND NOT EXISTS (SELECT 1 FROM hafbe_app.account_vest_stats_cache avs WHERE avs.account_id = cab.account)
    AND NOT EXISTS (SELECT 1 FROM hafbe_app.current_witnesses cw WHERE cw.witness_id = cab.account)
  ORDER BY cab.account
  LIMIT 1;

  -- A tracked account no refresh of _block can reach: a proxy setter nobody proxies
  -- to, with no vote event in today's window, that _block does not name.
  SELECT cap.account_id INTO _canary
  FROM hafbe_app.current_account_proxies cap
  WHERE NOT cap.account_id = ANY(_named || _chain)
    AND NOT EXISTS (SELECT 1 FROM hafbe_app.current_account_proxies c2 WHERE c2.proxy_id = cap.account_id)
    AND NOT EXISTS (
      SELECT 1 FROM hafbe_app.witness_votes_history wvh
      WHERE wvh.voter_id = cap.account_id
        AND wvh.source_op >= hafd.operation_id(hafbe_app.witness_votes_cache_window_start(), 0)
    )
  ORDER BY cap.account_id
  LIMIT 1;

  -- The newest routed fill_vesting_withdraw depositing vests into a tracked account no
  -- other operation of its block names, directly or through a proxy chain, in a block
  -- the incremental path takes.
  FOR _candidate IN
    SELECT ov.block_num, fa.id AS from_id, ta.id AS to_id, ta.name AS to_name,
           (ov.body_value->'deposited'->>'amount')::BIGINT AS deposited
    FROM hafbe_app.operations_view ov
    JOIN hafbe_app.accounts_view fa ON fa.name = ov.body_value->>'from_account'
    JOIN hafbe_app.accounts_view ta ON ta.name = ov.body_value->>'to_account'
    WHERE ov.op_type_id = (SELECT ot.id FROM hafd.operation_types ot WHERE ot.name = 'hive::protocol::fill_vesting_withdraw_operation')
      AND ov.block_num <= _head
      AND ov.body_value->>'from_account' <> ov.body_value->>'to_account'
      AND ov.body_value->'deposited'->>'nai' = '@@000000037'
      AND EXISTS (SELECT 1 FROM hafbe_app.account_vest_stats_cache avs WHERE avs.account_id = ta.id)
      AND EXISTS (SELECT 1 FROM current_account_balances cab WHERE cab.account = ta.id AND cab.nai = btracker_backend.nai_vests())
    ORDER BY ov.block_num DESC
    LIMIT 200
  LOOP
    IF NOT pg_temp.has_full_op(_candidate.block_num)
       AND NOT _canary = ANY(pg_temp.named(_candidate.block_num))
       AND pg_temp.times_named(_candidate.block_num, _candidate.to_name) = 1
       -- Nor as the proxy ancestor of another account the block names, which the
       -- refresh would add without the withdrawal.
       AND NOT EXISTS (
         SELECT 1 FROM unnest(pg_temp.named(_candidate.block_num)) AS n (account_id)
         WHERE n.account_id <> _candidate.to_id
           AND _candidate.to_id = ANY(pg_temp.with_proxies(n.account_id))
       ) THEN
      _wd_block      := _candidate.block_num;
      _wd_from       := _candidate.from_id;
      _wd_to         := _candidate.to_id;
      _wd_vests      := _candidate.deposited;
      EXIT;
    END IF;
  END LOOP;

  IF _other IS NULL OR _full_block IS NULL OR _witness IS NULL OR _voter IS NULL OR _canary IS NULL OR _wd_block IS NULL THEN
    RAISE EXCEPTION 'the synced data lacks a case: other block %, full-recompute block %, new witness %, proposal voter %, canary %, routed withdrawal block %',
      _other, _full_block, _witness, _voter, _canary, _wd_block;
  END IF;
  RAISE NOTICE 'block % names proxy setter % (chain %); other block %; full-recompute block %; new witness %; proposal voter %; canary %; block % routes % vests from % to tracked account %',
    _block, _setter, _chain, _other, _full_block, _witness, _voter, _canary, _wd_block, _wd_vests, _wd_from, _wd_to;

  PERFORM pg_temp.expect_match('initial caches');

  ------------------------------------------------------------------------------
  -- An ordinary block: the incremental path.
  ------------------------------------------------------------------------------
  PERFORM pg_temp.set_last(_block - 1);
  PERFORM pg_temp.add_vests(_setter, _bump);

  IF pg_temp.refresh_took_full(_block, _canary) THEN
    RAISE EXCEPTION 'ordinary block: the refresh recomputed the caches in full instead of updating them';
  END IF;
  -- before_wr holds the ranks of the full recompute before the block.
  IF NOT EXISTS (
    SELECT 1 FROM hafbe_app.witness_rank_cache r JOIN before_wr b USING (witness_id) WHERE r.rank <> b.rank
  ) THEN
    RAISE EXCEPTION 'ordinary block: no witness rank moved, so the rank update is not exercised';
  END IF;
  PERFORM pg_temp.expect_match('ordinary block');

  ------------------------------------------------------------------------------
  -- A fork: _block's balance change is reverted and the block handed over next,
  -- _other, is below it and does not name the account.
  ------------------------------------------------------------------------------
  PERFORM pg_temp.set_last(_block);
  PERFORM pg_temp.add_vests(_setter, -_bump);
  PERFORM pg_temp.expect_incremental_misses('fork', _other);
  PERFORM pg_temp.refresh(_other);
  PERFORM pg_temp.expect_match('fork');

  ------------------------------------------------------------------------------
  -- A restart gap: the two blocks before _other were processed without a refresh.
  ------------------------------------------------------------------------------
  PERFORM pg_temp.set_last(_other - 3);
  PERFORM pg_temp.add_vests(_setter, _bump);
  PERFORM pg_temp.expect_incremental_misses('restart gap', _other);
  PERFORM pg_temp.refresh(_other);
  PERFORM pg_temp.expect_match('restart gap');

  ------------------------------------------------------------------------------
  -- A new witness: process_witness_stats() adds a current_witnesses row for an
  -- account the block names.
  ------------------------------------------------------------------------------
  INSERT INTO hafbe_app.current_witnesses (witness_id) VALUES (_witness);
  PERFORM pg_temp.expect_incremental_misses('new witness', _block);
  PERFORM pg_temp.set_last(_other - 1);
  PERFORM pg_temp.refresh(_other);
  PERFORM pg_temp.expect_match('new witness');

  ------------------------------------------------------------------------------
  -- remove_proposal deleting the only proposal vote of an otherwise untracked voter.
  ------------------------------------------------------------------------------
  INSERT INTO hafbe_app.current_proposals
    (proposal_id, creator_id, receiver_id, start_date, end_date, daily_pay, subject, permlink, source_op)
  VALUES
    (2147483000, _voter, _voter, '2016-01-01', '2099-01-01', 1000, 'test', 'test', 0);
  INSERT INTO hafbe_app.current_proposal_votes (voter_id, proposal_id, source_op)
  VALUES (_voter, 2147483000, 0);
  -- The vote's own block carries update_proposal_votes: a full recompute.
  PERFORM pg_temp.differences_from_full();
  IF NOT EXISTS (SELECT 1 FROM hafbe_app.account_vest_stats_cache WHERE account_id = _voter) THEN
    RAISE EXCEPTION 'proposal vote: the voter is not tracked';
  END IF;

  DELETE FROM hafbe_app.current_proposal_votes WHERE proposal_id = 2147483000;
  UPDATE hafbe_app.current_proposals SET removed = TRUE WHERE proposal_id = 2147483000;
  PERFORM pg_temp.expect_incremental_misses('remove_proposal', _block);

  IF has_table_privilege('hafd.operations', 'INSERT') THEN
    PERFORM pg_temp.add_op(_block, 'hive::protocol::remove_proposal_operation', jsonb_build_object(
      'proposal_owner', (SELECT name FROM hafbe_app.accounts_view WHERE id = _voter),
      'proposal_ids', jsonb_build_array(2147483000),
      'extensions', jsonb_build_array()));
    PERFORM pg_temp.set_last(_block - 1);
    PERFORM pg_temp.refresh(_block);
    PERFORM pg_temp.expect_match('remove_proposal');
  ELSE
    RAISE NOTICE 'remove_proposal: SKIPPED adding a remove_proposal operation: % may not write hafd.operations; the block below carries another full-recompute operation', current_user;
  END IF;
  -- Whatever the operation, a block forcing the full recompute drops the voter.
  PERFORM pg_temp.set_last(_full_block - 1);
  PERFORM pg_temp.refresh(_full_block);
  PERFORM pg_temp.expect_match('full-recompute operation');

  ------------------------------------------------------------------------------
  -- A window move: the caches were last refreshed with another daily-change window
  -- than the successor block's.
  ------------------------------------------------------------------------------
  PERFORM pg_temp.set_state(_block - 1, _window - 1);
  IF NOT pg_temp.refresh_took_full(_block, _canary) THEN
    RAISE EXCEPTION 'window move: the refresh updated the caches instead of recomputing them in full';
  END IF;
  PERFORM pg_temp.expect_match('window move');

  ------------------------------------------------------------------------------
  -- A routed withdrawal: _wd_block names _wd_to only through the fill_vesting_withdraw
  -- that moves its vests. Only the receiving side is simulated.
  ------------------------------------------------------------------------------
  PERFORM pg_temp.set_last(_wd_block - 1);
  PERFORM pg_temp.add_vests(_wd_to, _wd_vests);
  _to_v := (SELECT vests FROM hafbe_app.account_vest_stats_cache WHERE account_id = _wd_to);
  IF pg_temp.refresh_took_full(_wd_block, _canary) THEN
    RAISE EXCEPTION 'routed withdrawal: the refresh recomputed the caches in full instead of updating them';
  END IF;
  IF (SELECT vests FROM hafbe_app.account_vest_stats_cache WHERE account_id = _wd_to) = _to_v THEN
    RAISE EXCEPTION 'routed withdrawal: the refresh left the vests of account % as they were', _wd_to;
  END IF;
  PERFORM pg_temp.expect_match('routed withdrawal');
END
$$;

ROLLBACK;
