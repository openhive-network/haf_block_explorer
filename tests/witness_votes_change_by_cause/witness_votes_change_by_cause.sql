-- Witness vote change by cause on synthetic events.
--
-- Picks accounts no vote, proxy or recent VESTS change of the synced chain touches,
-- gives them a state and a window of events by writing hafbe's and the balance
-- tracker's tables, and checks hafbe_app.witness_votes_change_by_cause_of() against
-- values derived by hand from the scenario below. Two witnesses, X and Y:
--
--   before the window   A, C and H vote for X; I and L vote for Y. D -> E -> A and
--                       G -> E, K -> A proxy. Base VESTS: A 980 (15 of them still
--                       delayed), B 600, C 250, D 45, E 200, F 30, G 70, H 80,
--                       I 400, K 60, L 90.
--   t1   C claims 40 VESTS                            X claimed_reward  +40
--   t2   B votes for X, at 600 VESTS                  X votes_cast     +600
--   t3   B powers down 100 VESTS                      X power_down     -100
--   t4   C removes its vote, at 290 VESTS             X votes_removed  -290
--   t5   C claims 10 VESTS (no longer backs X)        -
--   t6   A's producer reward, 20 VESTS                X producer_reward +20
--   t7   A's 15 delayed VESTS mature (delayed_voting) X power_up        +15
--   t8   D claims 5 VESTS: D -> E -> A, two levels     X claimed_reward   +5
--   t9   F sets its proxy to E: F -> E -> A            X proxy           +30
--   t10  G clears its proxy (was E)                   X proxy           -70
--   t11  H sets its proxy to A: its vote for X is     X proxy      -80, +80
--        removed and its weight reaches X through A
--   t12  I's votes expire                             Y expired        -400
--   t13  K's proxy expires (was A)                    X expired         -60
--   t14  L declines its voting rights                 Y declined        -90
--
-- X totals +190 (from A 1340 + C 250 + H 80 to A 1360 + B 500), Y -490. B's vote and
-- power-down in one window are counted once: its vote at the weight it had then.
--
-- t7, t11, t12, t13 and t14 need operations of their type in hafd.operations; when
-- the role may not write it (only haf_admin may), they are left out, the scenario
-- loses them (X +235: A 1295 + C 250 to A 1280 + B 500) and the output says which.
--
-- Then refresh_witness_votes_change_by_cause() over the whole chain: every
-- witness's total row is the sum of its cause rows, in both windows, and X's 7-day
-- breakdown as hafbe_backend.witness_votes_change_breakdown() returns it.
--
-- Needs a synced hafbe and the balance tracker's schema first on the search path.
-- Everything is rolled back.

BEGIN;

CREATE TEMP TABLE scenario_accounts (part TEXT PRIMARY KEY, id INT NOT NULL, account_name TEXT NOT NULL);

-- The id of a new operation appended to _block, after its last one. Written to
-- hafd.operations when _write.
CREATE FUNCTION pg_temp.op_at(_block INT, _write BOOLEAN, _op_name TEXT, _body JSONB)
RETURNS BIGINT
LANGUAGE plpgsql
AS $$
DECLARE
  _id BIGINT := (
    SELECT hafd.operation_id(_block, (COALESCE(max(o.id) - hafd.operation_id(_block, 0), -1) + 1)::INT)
    FROM hafd.operations o
    WHERE o.id >= hafd.operation_id(_block, 0) AND o.id < hafd.operation_id(_block + 1, 0)
  );
BEGIN
  IF _write THEN
    INSERT INTO hafd.operations (id, trx_in_block, op_pos, op_type_id, body_value)
    VALUES (
      _id, 0, (_id - hafd.operation_id(_block, 0))::INT,
      (SELECT ot.id FROM hafd.operation_types ot WHERE ot.name = _op_name),
      _body
    );
  END IF;
  RETURN _id;
END
$$;

CREATE FUNCTION pg_temp.account(_part TEXT)
RETURNS INT
LANGUAGE sql
AS $$
  SELECT s.id FROM scenario_accounts s WHERE s.part = _part;
$$;

-- A VESTS balance row of _part after the account's last one.
CREATE FUNCTION pg_temp.set_vests(_part TEXT, _balance BIGINT, _op_type_id INT, _source_op BIGINT)
RETURNS VOID
LANGUAGE sql
AS $$
  INSERT INTO account_balance_history (account, nai, op_type_id, balance, balance_seq_no, source_op)
  SELECT
    pg_temp.account(_part),
    btracker_backend.nai_vests(),
    _op_type_id,
    _balance,
    COALESCE((
      SELECT max(h.balance_seq_no) FROM account_balance_history h
      WHERE h.account = pg_temp.account(_part) AND h.nai = btracker_backend.nai_vests()
    ), 0) + 1,
    _source_op;
  INSERT INTO current_account_balances (account, nai, balance, balance_change_count, source_op)
  VALUES (pg_temp.account(_part), btracker_backend.nai_vests(), _balance, 1, _source_op)
  ON CONFLICT ON CONSTRAINT pk_current_account_balances DO UPDATE SET
    balance   = EXCLUDED.balance,
    source_op = EXCLUDED.source_op;
$$;

CREATE FUNCTION pg_temp.vote(_voter TEXT, _witness TEXT, _approve BOOLEAN, _source_op BIGINT)
RETURNS VOID
LANGUAGE sql
AS $$
  INSERT INTO hafbe_app.witness_votes_history (witness_id, voter_id, approve, source_op)
  VALUES (pg_temp.account(_witness), pg_temp.account(_voter), _approve, _source_op);
$$;

CREATE FUNCTION pg_temp.proxy(_account TEXT, _proxy TEXT, _set BOOLEAN, _source_op BIGINT)
RETURNS VOID
LANGUAGE sql
AS $$
  INSERT INTO hafbe_app.account_proxies_history (account_id, proxy_id, proxy, source_op)
  VALUES (pg_temp.account(_account), pg_temp.account(_proxy), _set, _source_op);
$$;

-- The function's rows for one witness against the expected (cause, vests, voters).
CREATE FUNCTION pg_temp.expect(_case TEXT, _first_block INT, _witness TEXT, _expected JSONB)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
  _diff TEXT;
BEGIN
  WITH actual AS (
    SELECT c.cause, c.vests, c.voters
    FROM hafbe_app.witness_votes_change_by_cause_of(_first_block) c
    WHERE c.witness_id = pg_temp.account(_witness)
  ),
  expected AS (
    SELECT e.key AS cause, (e.value ->> 0)::BIGINT AS vests, (e.value ->> 1)::INT AS voters
    FROM jsonb_each(_expected) e
  )
  SELECT string_agg(format('%s: expected %s, got %s', COALESCE(e.cause, a.cause),
                           COALESCE(format('%s VESTS / %s voters', e.vests, e.voters), 'no row'),
                           COALESCE(format('%s VESTS / %s voters', a.vests, a.voters), 'no row')), '; ')
  INTO _diff
  FROM expected e
  FULL JOIN actual a ON a.cause = e.cause
  WHERE (e.vests, e.voters) IS DISTINCT FROM (a.vests, a.voters);

  IF _diff IS NOT NULL THEN
    RAISE EXCEPTION '%, witness %: %', _case, _witness, _diff;
  END IF;
  RAISE NOTICE '%, witness %: every cause matches', _case, _witness;
END
$$;

DO $$
DECLARE
  _head        INT  := (SELECT c.current_block_num FROM hafd.contexts c WHERE c.name = 'hafbe_app');
  _week_start  INT;
  _before      INT;      -- a block before both windows: the scenario's prior state
  _window      INT;      -- the first block of the scenario's window
  _write_ops   BOOLEAN := has_table_privilege('hafd.operations', 'INSERT');
  _fill        INT  := btracker_backend.op_fill_vesting_withdraw();
  _producer    INT  := hafbe_backend.op_producer_reward();
  _claim       INT  := btracker_backend.op_claim_reward_balance();
  _other       INT  := btracker_backend.op_transfer_to_vesting();
  _op          BIGINT;
  _parts       TEXT[] := ARRAY['X', 'Y', 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'K', 'L'];
  _picked      INT;
  _mismatches  INT;
  _breakdown   JSON;
BEGIN
  IF _head IS NULL THEN
    RAISE EXCEPTION 'hafbe_app has processed no block: sync it first';
  END IF;
  _week_start := hafbe_app.witness_votes_change_week_start(_head);
  _before := _week_start - 10;
  _window := _head - 100;
  IF _before < 1 OR _window <= _before THEN
    RAISE EXCEPTION 'the synced chain (head %) is too short for the scenario', _head;
  END IF;

  -- Accounts nothing of the window touches, and no vote or proxy ever names.
  INSERT INTO scenario_accounts (part, id, account_name)
  SELECT r.part, c.id, c.name
  FROM unnest(_parts) WITH ORDINALITY AS r (part, n)
  JOIN (
    SELECT av.id, av.name, ROW_NUMBER() OVER (ORDER BY av.id DESC) AS n
    FROM (
      SELECT av.id, av.name
      FROM hafbe_app.accounts_view av
      WHERE av.id > 100
        AND NOT EXISTS (SELECT 1 FROM hafbe_app.current_witnesses cw WHERE cw.witness_id = av.id)
        AND NOT EXISTS (SELECT 1 FROM hafbe_app.witness_votes_history h WHERE h.voter_id = av.id OR h.witness_id = av.id)
        AND NOT EXISTS (SELECT 1 FROM hafbe_app.account_proxies_history p WHERE p.account_id = av.id OR p.proxy_id = av.id)
        AND NOT EXISTS (
          SELECT 1 FROM account_balance_history b
          WHERE b.account = av.id
            AND b.nai = btracker_backend.nai_vests()
            AND hafd.operation_id_to_block_num(b.source_op) >= _before
        )
      ORDER BY av.id DESC
      LIMIT 13
    ) av
  ) c ON c.n = r.n;
  GET DIAGNOSTICS _picked = ROW_COUNT;
  IF _picked <> cardinality(_parts) THEN
    RAISE EXCEPTION 'found % untouched accounts, the scenario needs %', _picked, cardinality(_parts);
  END IF;
  DELETE FROM account_withdraws w WHERE w.account IN (SELECT s.id FROM scenario_accounts s);

  -- The prior state.
  _op := pg_temp.op_at(_before, FALSE, NULL, NULL);
  PERFORM pg_temp.set_vests('A', 980, _other, _op);
  PERFORM pg_temp.set_vests('B', 600, _other, _op);
  PERFORM pg_temp.set_vests('C', 250, _other, _op);
  PERFORM pg_temp.set_vests('D', 45, _other, _op);
  PERFORM pg_temp.set_vests('E', 200, _other, _op);
  PERFORM pg_temp.set_vests('F', 30, _other, _op);
  PERFORM pg_temp.set_vests('G', 70, _other, _op);
  PERFORM pg_temp.set_vests('H', 80, _other, _op);
  PERFORM pg_temp.set_vests('I', 400, _other, _op);
  PERFORM pg_temp.set_vests('K', 60, _other, _op);
  PERFORM pg_temp.set_vests('L', 90, _other, _op);
  PERFORM pg_temp.proxy('G', 'E', TRUE, _op);
  PERFORM pg_temp.proxy('K', 'A', TRUE, _op);
  -- What process_witness_votes() leaves after the window (current tables).
  INSERT INTO hafbe_app.current_witness_votes (witness_id, voter_id, source_op)
  VALUES (pg_temp.account('X'), pg_temp.account('A'), _op);
  INSERT INTO hafbe_app.current_account_proxies (account_id, proxy_id, source_op)
  VALUES (pg_temp.account('D'), pg_temp.account('E'), _op),
         (pg_temp.account('E'), pg_temp.account('A'), _op);
  IF NOT _write_ops THEN
    -- Without t11-t13, H still votes for X, I for Y, and K still proxies to A.
    INSERT INTO hafbe_app.current_witness_votes (witness_id, voter_id, source_op)
    VALUES (pg_temp.account('X'), pg_temp.account('H'), _op),
           (pg_temp.account('Y'), pg_temp.account('I'), _op),
           (pg_temp.account('Y'), pg_temp.account('L'), _op);
    INSERT INTO hafbe_app.current_account_proxies (account_id, proxy_id, source_op)
    VALUES (pg_temp.account('K'), pg_temp.account('A'), _op);
  END IF;

  -- The window, one event per block. A's 15 delayed VESTS are delayed until t7.
  IF _write_ops THEN
    INSERT INTO account_withdraws (account, delayed_vests) VALUES (pg_temp.account('A'), 15);
  END IF;
  PERFORM pg_temp.set_vests('C', 290, _claim, pg_temp.op_at(_window + 1, FALSE, NULL, NULL));
  _op := pg_temp.op_at(_window + 2, FALSE, NULL, NULL);
  PERFORM pg_temp.vote('B', 'X', TRUE, _op);
  INSERT INTO hafbe_app.current_witness_votes (witness_id, voter_id, source_op)
  VALUES (pg_temp.account('X'), pg_temp.account('B'), _op);
  PERFORM pg_temp.set_vests('B', 500, _fill, pg_temp.op_at(_window + 3, FALSE, NULL, NULL));
  -- An approval made before the window, removed in it.
  PERFORM pg_temp.vote('C', 'X', FALSE, pg_temp.op_at(_window + 4, FALSE, NULL, NULL));
  PERFORM pg_temp.set_vests('C', 300, _claim, pg_temp.op_at(_window + 5, FALSE, NULL, NULL));
  PERFORM pg_temp.set_vests('A', 1000, _producer, pg_temp.op_at(_window + 6, FALSE, NULL, NULL));
  IF _write_ops THEN
    PERFORM pg_temp.op_at(_window + 7, TRUE, 'hive::protocol::delayed_voting_operation',
      jsonb_build_object('voter', (SELECT s.account_name FROM scenario_accounts s WHERE s.part = 'A'), 'votes', 15));
    UPDATE account_withdraws SET delayed_vests = 0 WHERE account = pg_temp.account('A');
  END IF;
  PERFORM pg_temp.set_vests('D', 50, _claim, pg_temp.op_at(_window + 8, FALSE, NULL, NULL));
  _op := pg_temp.op_at(_window + 9, FALSE, NULL, NULL);
  PERFORM pg_temp.proxy('F', 'E', TRUE, _op);
  INSERT INTO hafbe_app.current_account_proxies (account_id, proxy_id, source_op)
  VALUES (pg_temp.account('F'), pg_temp.account('E'), _op);
  PERFORM pg_temp.proxy('G', 'E', FALSE, pg_temp.op_at(_window + 10, FALSE, NULL, NULL));
  IF _write_ops THEN
    _op := pg_temp.op_at(_window + 11, TRUE, 'hive::protocol::account_witness_proxy_operation', '{}');
    PERFORM pg_temp.proxy('H', 'A', TRUE, _op);
    PERFORM pg_temp.vote('H', 'X', FALSE, _op);
    INSERT INTO hafbe_app.current_account_proxies (account_id, proxy_id, source_op)
    VALUES (pg_temp.account('H'), pg_temp.account('A'), _op);
    PERFORM pg_temp.vote('I', 'Y', FALSE,
      pg_temp.op_at(_window + 12, TRUE, 'hive::protocol::expired_account_notification_operation', '{}'));
    PERFORM pg_temp.proxy('K', 'A', FALSE,
      pg_temp.op_at(_window + 13, TRUE, 'hive::protocol::expired_account_notification_operation', '{}'));
    PERFORM pg_temp.vote('L', 'Y', FALSE,
      pg_temp.op_at(_window + 14, TRUE, 'hive::protocol::declined_voting_rights_operation', '{}'));
    PERFORM pg_temp.expect('the window', _window, 'X', '{
      "votes_cast": [600, 1], "power_down": [-100, 1], "votes_removed": [-290, 1],
      "claimed_reward": [45, 2], "producer_reward": [20, 1], "power_up": [15, 1],
      "proxy": [-40, 2], "expired": [-60, 1], "total": [190, 4]}');
    PERFORM pg_temp.expect('the window', _window, 'Y', '{
      "expired": [-400, 1], "declined": [-90, 1], "total": [-490, 2]}');
  ELSE
    RAISE NOTICE 'SKIPPED power_up (t7), the proxy cascade (t11), expired (t12, t13) and declined (t14): % may not write hafd.operations', current_user;
    PERFORM pg_temp.expect('the window', _window, 'X', '{
      "votes_cast": [600, 1], "power_down": [-100, 1], "votes_removed": [-290, 1],
      "claimed_reward": [45, 2], "producer_reward": [20, 1],
      "proxy": [-40, 1], "total": [235, 3]}');
    PERFORM pg_temp.expect('the window', _window, 'Y', '{}');
  END IF;

  -- A window starting after the events sees none of them.
  PERFORM pg_temp.expect('a window after the events', _window + 20, 'X', '{}');

  -- The refresh over the synced chain and the scenario: totals are the sum of causes.
  PERFORM hafbe_app.refresh_witness_votes_change_by_cause(_head);
  SELECT count(*)
  INTO _mismatches
  FROM (
    SELECT c.witness_id, c.time_window
    FROM hafbe_app.witness_votes_change_by_cause c
    GROUP BY c.witness_id, c.time_window
    HAVING SUM(c.vests) FILTER (WHERE c.cause = 'total') IS DISTINCT FROM SUM(c.vests) FILTER (WHERE c.cause <> 'total')
  ) m;
  IF _mismatches <> 0 THEN
    RAISE EXCEPTION 'refresh: % witness windows have a total other than the sum of their causes', _mismatches;
  END IF;
  IF (SELECT s.as_of_block FROM hafbe_app.witness_votes_change_by_cause_state s) IS DISTINCT FROM _head THEN
    RAISE EXCEPTION 'refresh: the state does not hold block %', _head;
  END IF;
  RAISE NOTICE 'refresh: % rows, every total is the sum of its causes',
    (SELECT count(*) FROM hafbe_app.witness_votes_change_by_cause);

  -- The 7-day window reaches back past the scenario's window: X's breakdown holds it.
  SELECT b.votes_change_breakdown INTO _breakdown
  FROM hafbe_backend.witness_votes_change_breakdown(ARRAY[pg_temp.account('X')]) b;
  IF (_breakdown ->> 'as_of_block')::INT IS DISTINCT FROM _head
     OR _breakdown -> '7d' ->> 'total' IS DISTINCT FROM (CASE WHEN _write_ops THEN '190' ELSE '235' END)
     OR _breakdown -> '7d' ->> 'votes_cast' IS DISTINCT FROM '600'
     OR _breakdown -> '7d' ->> 'power_down' IS DISTINCT FROM '-100'
     OR json_typeof(_breakdown -> '7d' -> 'rank_start') IS DISTINCT FROM 'number'
     OR (SELECT count(*) FROM json_object_keys(_breakdown -> '7d')) <> 12
     OR (SELECT count(*) FROM json_object_keys(_breakdown -> 'today')) <> 12 THEN
    RAISE EXCEPTION 'votes_change_breakdown of X is not the scenario: %', _breakdown;
  END IF;
  RAISE NOTICE 'votes_change_breakdown: %', _breakdown;
END
$$;

ROLLBACK;
