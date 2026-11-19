-- Witness vote change by cause on synthetic events.
--
-- Picks accounts no vote, proxy or recent VESTS change of the synced chain touches,
-- gives them a state and a window of events, and checks
-- hafbe_app.witness_votes_change_by_cause_of() against values derived by hand from
-- the scenario below. Votes, proxies, expiries and declines go through hafbe's own
-- parsers (process_vote_op, process_proxy_ops, process_expired_accounts) in the
-- order hived emits their operations; VESTS changes are written to the balance
-- tracker's tables. Four witnesses, X, Y, Z and W:
--
--   before the window   A, C and H vote for X; I and L vote for Y; P for Z; Q for W.
--                       D -> E -> A, G -> E, K -> A, S -> P, M -> P, N -> Q and
--                       R0 -> R1 -> R2 -> R3 -> R4 -> Q proxy. U proxies to P, then
--                       switches to Q. Base VESTS: A 980 (15 of them still delayed),
--                       B 600, C 250, D 45, E 200, F 30, G 70, H 80, I 400, K 60,
--                       L 90, P 500, Q 700, S 300, U 200, M 120, N 130, R0 40,
--                       R1 60, R2 35, R3 45, R4 55, T 15.
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
--   t15  S switches its proxy from P to Q: hived      Z proxy          -300
--        pushes proxy_cleared for P after the switch  W proxy          +300
--   t16  S claims 10 VESTS, through Q                 W claimed_reward  +10
--   t17  U clears its proxy (Q, since its switch)     W proxy          -200
--   t18  M's account expires, clearing its proxy      Z expired        -120
--   t19  N declines its voting rights, clearing its   W declined       -130
--        proxy
--   t20  R1 claims 25 VESTS: four levels up to Q      W claimed_reward  +25
--   t21  R0 claims 7 VESTS: five levels, reaches no   -
--        voter
--   t22  T sets its proxy to R2: four levels to Q     W proxy           +15
--
-- X totals +190 (from A 1340 + C 250 + H 80 to A 1360 + B 500), Y -490, Z -420
-- (from P 920 to 500), W +20 (from Q 1225 to 1245). B's vote and power-down in one
-- window are counted once: its vote at the weight it had then.
--
-- t7, t11, t12, t13, t14, t18 and t19 need operations of their type in
-- hafd.operations (the cause of a removal is read from them); when the role may not
-- write it (only haf_admin may), they are left out, the scenario loses them (X +235:
-- A 1355 + C 250 + H 80 to A 1340 + H 80 + B 500; Y 0; Z -300; W +150) and the
-- output says which.
--
-- Then:
--   - every witness's total over the scenario's window against the change of its
--     votes computed independently from the same history (votes before the
--     window's first block and after the last processed one); the scenario's
--     witnesses must match exactly, any other witness may differ only where an
--     approximation of the file header applies, and the output names each;
--   - refresh_witness_votes_change_by_cause() over the whole chain: every total is
--     the sum of its causes (a sanity check: true by construction), the stored
--     windows reconcile like the scenario's, rank_start ranks every current witness
--     like rank, on its votes and voters at the window start of the refresh's block,
--     an unmoved witness differs from its rank only by the moved witnesses that
--     passed it (one without votes has rank_start = rank), rank_start does not
--     follow the witness vote cache after the refresh, and X's 7-day breakdown is
--     what hafbe_backend.witness_votes_change_breakdown() returns;
--   - the today window is votes_daily_change's, in UTC and America/New_York;
--   - a refresh that fails, by a statement timeout, an error or a cancel by request,
--     leaves the previous breakdown in place and does not fail
--     process_witness_votes_change_by_cause(), which does not attempt it again until
--     100 blocks later;
--   - a new UTC day triggers a refresh before 100 blocks have passed.
--
-- Needs a synced hafbe, the balance tracker's schema first on the search path and a
-- member of hafbe_owner. Everything is rolled back.

BEGIN;

CREATE TEMP TABLE scenario_accounts (part TEXT PRIMARY KEY, id INT NOT NULL, account_name TEXT NOT NULL);
CREATE TEMP TABLE scenario_ops (id BIGINT PRIMARY KEY);
CREATE TEMP TABLE scenario_settings (write_ops BOOLEAN NOT NULL, head INT NOT NULL);

CREATE FUNCTION pg_temp.account(_part TEXT)
RETURNS INT
LANGUAGE sql
STABLE
AS $$
  SELECT s.id FROM scenario_accounts s WHERE s.part = _part;
$$;

CREATE FUNCTION pg_temp.account_name(_part TEXT)
RETURNS TEXT
LANGUAGE sql
STABLE
AS $$
  SELECT s.account_name FROM scenario_accounts s WHERE s.part = _part;
$$;

-- The id of a new operation of _block, after the block's last one and the
-- scenario's. Written to hafd.operations when the role may and _op_name is given.
CREATE FUNCTION pg_temp.next_op(_block INT, _op_name TEXT DEFAULT NULL, _body JSONB DEFAULT NULL)
RETURNS BIGINT
LANGUAGE plpgsql
AS $$
DECLARE
  _first BIGINT := hafd.operation_id(_block, 0);
  _next  BIGINT := hafd.operation_id(_block + 1, 0);
  _id    BIGINT;
BEGIN
  _id := hafd.operation_id(_block, (GREATEST(
    COALESCE((SELECT max(o.id) FROM hafd.operations o WHERE o.id >= _first AND o.id < _next), _first - 1),
    COALESCE((SELECT max(s.id) FROM scenario_ops s WHERE s.id >= _first AND s.id < _next), _first - 1)
  ) + 1 - _first)::INT);
  INSERT INTO scenario_ops (id) VALUES (_id);
  IF _op_name IS NOT NULL AND (SELECT s.write_ops FROM scenario_settings s) THEN
    INSERT INTO hafd.operations (id, trx_in_block, op_pos, op_type_id, body_value)
    VALUES (
      _id, 0, (_id - _first)::INT,
      (SELECT ot.id FROM hafd.operation_types ot WHERE ot.name = 'hive::protocol::' || _op_name),
      _body
    );
  END IF;
  RETURN _id;
END
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

-- The operations hived emits, each applied by hafbe's parser as process_witness_votes() does.
CREATE FUNCTION pg_temp.op_vote(_block INT, _voter TEXT, _witness TEXT, _approve BOOLEAN)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
  _body JSONB := jsonb_build_object('account', pg_temp.account_name(_voter), 'witness', pg_temp.account_name(_witness), 'approve', _approve);
BEGIN
  PERFORM hafbe_backend.process_vote_op(_body, pg_temp.next_op(_block, 'account_witness_vote_operation', _body));
END
$$;

-- account_witness_proxy; _proxy NULL clears the proxy (an empty proxy name).
CREATE FUNCTION pg_temp.op_proxy(_block INT, _account TEXT, _proxy TEXT)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
  _body JSONB := jsonb_build_object('account', pg_temp.account_name(_account), 'proxy', COALESCE(pg_temp.account_name(_proxy), ''));
BEGIN
  PERFORM hafbe_backend.process_proxy_ops(_body, pg_temp.next_op(_block, 'account_witness_proxy_operation', _body), TRUE);
END
$$;

CREATE FUNCTION pg_temp.op_proxy_cleared(_block INT, _account TEXT, _proxy TEXT)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
  _body JSONB := jsonb_build_object('account', pg_temp.account_name(_account), 'proxy', pg_temp.account_name(_proxy));
BEGIN
  PERFORM hafbe_backend.process_proxy_ops(_body, pg_temp.next_op(_block, 'proxy_cleared_operation', _body), FALSE);
END
$$;

-- expired_account_notification_operation or declined_voting_rights_operation.
CREATE FUNCTION pg_temp.op_voting_rights_lost(_block INT, _account TEXT, _op_name TEXT)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
  _body JSONB := jsonb_build_object('account', pg_temp.account_name(_account));
BEGIN
  PERFORM hafbe_backend.process_expired_accounts(_body, pg_temp.next_op(_block, _op_name, _body));
END
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

-- ---------------------------------------------------------------------------------
-- The reconciliation: votes recomputed from the history tables at an operation id,
-- with none of witness_votes_change_by_cause_of()'s code.
-- ---------------------------------------------------------------------------------

-- Each account's proxy before operation _op, replaying its rows one by one: a set
-- names the proxy, a clear removes it when it names the proxy in force.
CREATE FUNCTION pg_temp.proxies_at(_op BIGINT)
RETURNS TABLE (account_id INT, proxy_id INT)
LANGUAGE sql
AS $$
  WITH RECURSIVE numbered AS MATERIALIZED (
    SELECT
      p.account_id,
      p.proxy_id,
      p.proxy,
      ROW_NUMBER() OVER (PARTITION BY p.account_id ORDER BY p.source_op) AS n
    FROM hafbe_app.account_proxies_history p
    WHERE p.source_op < _op
  ),
  replay AS (
    SELECT n.account_id, n.n, CASE WHEN n.proxy THEN n.proxy_id END AS state
    FROM numbered n
    WHERE n.n = 1
    UNION ALL
    SELECT
      n.account_id,
      n.n,
      CASE
        WHEN n.proxy THEN n.proxy_id
        WHEN n.proxy_id = r.state THEN NULL
        ELSE r.state
      END
    FROM replay r
    JOIN numbered n ON n.account_id = r.account_id AND n.n = r.n + 1
  )
  SELECT l.account_id, l.state
  FROM (
    SELECT DISTINCT ON (r.account_id) r.account_id, r.state
    FROM replay r
    ORDER BY r.account_id, r.n DESC
  ) l
  WHERE l.state IS NOT NULL;
$$;

-- Each proxying account and the account its weight reaches before _op: the first
-- one along its chain without a proxy, at most 4 hops up (none beyond).
CREATE FUNCTION pg_temp.tops_at(_op BIGINT)
RETURNS TABLE (account_id INT, voter_id INT)
LANGUAGE sql
AS $$
  WITH RECURSIVE proxies AS MATERIALIZED (
    SELECT p.account_id, p.proxy_id FROM pg_temp.proxies_at(_op) p
  ),
  walk AS (
    SELECT p.account_id, p.proxy_id AS at_id, 1 AS hops FROM proxies p
    UNION ALL
    SELECT w.account_id, p.proxy_id, w.hops + 1
    FROM walk w
    JOIN proxies p ON p.account_id = w.at_id
    WHERE w.hops < 4
  )
  SELECT w.account_id, w.at_id
  FROM walk w
  WHERE NOT EXISTS (SELECT 1 FROM proxies p WHERE p.account_id = w.at_id);
$$;

-- Each witness's voters before _op, and every account whose weight reaches one.
CREATE FUNCTION pg_temp.members_at(_op BIGINT)
RETURNS TABLE (witness_id INT, account_id INT)
LANGUAGE sql
AS $$
  WITH voters AS MATERIALIZED (
    SELECT v.voter_id, v.witness_id
    FROM (
      SELECT DISTINCT ON (h.voter_id, h.witness_id) h.voter_id, h.witness_id, h.approve
      FROM hafbe_app.witness_votes_history h
      WHERE h.source_op < _op
      ORDER BY h.voter_id, h.witness_id, h.source_op DESC
    ) v
    WHERE v.approve
  )
  SELECT v.witness_id, v.voter_id FROM voters v
  UNION
  SELECT v.witness_id, t.account_id
  FROM voters v
  JOIN pg_temp.tops_at(_op) t ON t.voter_id = v.voter_id;
$$;

-- An account's delayed VESTS before _op: those of now plus the delayed_voting
-- since. Power-ups adding delayed VESTS since are not undone: the CI chain predates
-- delayed voting.
CREATE FUNCTION pg_temp.delayed_at(_account INT, _op BIGINT)
RETURNS BIGINT
LANGUAGE sql
AS $$
  SELECT
    COALESCE((SELECT w.delayed_vests::BIGINT FROM account_withdraws w WHERE w.account = _account), 0)
    + COALESCE((
      SELECT SUM((o.body_value ->> 'votes')::BIGINT)
      FROM hafbe_app.operations_view o
      WHERE o.op_type_id = btracker_backend.op_delayed_voting()
        AND o.block_num >= hafd.operation_id_to_block_num(_op)
        AND o.id >= _op
        AND o.body_value ->> 'voter' = (SELECT av.name FROM hafbe_app.accounts_view av WHERE av.id = _account)
    ), 0)::BIGINT;
$$;

-- An account's governance weight of its own before _op: its last VESTS balance
-- before it minus its delayed VESTS then.
CREATE FUNCTION pg_temp.own_at(_account INT, _op BIGINT)
RETURNS BIGINT
LANGUAGE sql
AS $$
  SELECT
    COALESCE((
      SELECT h.balance::BIGINT
      FROM account_balance_history h
      WHERE h.account = _account
        AND h.nai = btracker_backend.nai_vests()
        AND h.source_op < _op
      ORDER BY h.balance_seq_no DESC
      LIMIT 1
    ), 0)
    - pg_temp.delayed_at(_account, _op);
$$;

-- Each witness's total for a window starting at _first_block (in recon_totals)
-- against its votes after the last processed block minus its votes before
-- _first_block. A witness that differs must be explained by an approximation the
-- file header documents, found among the accounts whose weight reached it at either
-- end:
--   proxy chain    an account changed its proxy in the window and has accounts
--                  proxying to it, or proxies to an account that changed its own
--                  (chains above an account are the current ones; the weight a
--                  change moves leaves out later changes of its proxiers)
--   delayed VESTS  a power-down by an account with delayed VESTS
--   other VESTS    a VESTS change by an operation the breakdown does not read
--                  (immediate power-ups and VESTS rewards before HF24 / HF19)
-- The scenario's witnesses (_exact) must match exactly. Raises naming every witness
-- that differs otherwise.
CREATE FUNCTION pg_temp.reconcile(_label TEXT, _first_block INT, _exact INT[])
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
  _start_op BIGINT := hafd.operation_id(_first_block, 0);
  _end_op   BIGINT := hafd.operation_id((SELECT s.head FROM scenario_settings s) + 1, 0);
  _fill     INT    := btracker_backend.op_fill_vesting_withdraw();
  _read_ops INT[]  := ARRAY[btracker_backend.op_fill_vesting_withdraw(), hafbe_backend.op_producer_reward(), btracker_backend.op_claim_reward_balance()];
  _compared INT;
  _exact_n  INT;
  _summary  TEXT;
  _failures TEXT;
BEGIN
  IF to_regclass('pg_temp.recon_members') IS NOT NULL THEN
    DROP TABLE recon_members, recon_own, recon_proxies, recon_diffs, recon_flags;
  END IF;
  CREATE TEMP TABLE recon_members AS
    SELECT 'start'::TEXT AS at, m.witness_id, m.account_id FROM pg_temp.members_at(_start_op) m
    UNION ALL
    SELECT 'end', m.witness_id, m.account_id FROM pg_temp.members_at(_end_op) m;
  CREATE TEMP TABLE recon_own AS
    SELECT a.at, a.account_id, pg_temp.own_at(a.account_id, CASE a.at WHEN 'start' THEN _start_op ELSE _end_op END) AS own
    FROM (SELECT DISTINCT m.at, m.account_id FROM recon_members m) a;
  CREATE TEMP TABLE recon_diffs AS
    SELECT
      COALESCE(t.witness_id, c.witness_id) AS witness_id,
      COALESCE(t.vests, 0) AS total,
      COALESCE(c.change, 0) AS change
    FROM recon_totals t
    FULL JOIN (
      SELECT m.witness_id, SUM(CASE m.at WHEN 'end' THEN o.own ELSE -o.own END)::BIGINT AS change
      FROM recon_members m
      JOIN recon_own o ON o.at = m.at AND o.account_id = m.account_id
      GROUP BY m.witness_id
    ) c ON c.witness_id = t.witness_id;

  SELECT count(*), count(*) FILTER (WHERE d.total = d.change) INTO _compared, _exact_n FROM recon_diffs d;

  CREATE TEMP TABLE recon_proxies AS
    SELECT 'start'::TEXT AS at, p.account_id, p.proxy_id FROM pg_temp.proxies_at(_start_op) p
    UNION ALL
    SELECT 'end', p.account_id, p.proxy_id FROM pg_temp.proxies_at(_end_op) p;
  -- The approximations that apply to each account of a witness that differs.
  CREATE TEMP TABLE recon_flags AS
    SELECT
      a.account_id,
      EXISTS (
        SELECT 1 FROM hafbe_app.account_proxies_history p
        WHERE p.account_id = a.account_id AND p.source_op >= _start_op AND p.source_op < _end_op
      ) AND (
        EXISTS (SELECT 1 FROM recon_proxies r WHERE r.proxy_id = a.account_id)
        OR EXISTS (
          SELECT 1
          FROM recon_proxies r
          JOIN hafbe_app.account_proxies_history p
            ON p.account_id = r.proxy_id AND p.source_op >= _start_op AND p.source_op < _end_op
          WHERE r.account_id = a.account_id
        )
      ) AS proxy_chain,
      EXISTS (
        SELECT 1 FROM account_balance_history h
        WHERE h.account = a.account_id AND h.nai = btracker_backend.nai_vests()
          AND h.source_op >= _start_op AND h.source_op < _end_op AND h.op_type_id = _fill
      ) AND (
        pg_temp.delayed_at(a.account_id, _start_op) > 0 OR pg_temp.delayed_at(a.account_id, _end_op) > 0
      ) AS delayed_vests,
      EXISTS (
        SELECT 1
        FROM (
          SELECT h.op_type_id, h.balance, LAG(h.balance) OVER (ORDER BY h.balance_seq_no) AS previous_balance, h.source_op
          FROM account_balance_history h
          WHERE h.account = a.account_id AND h.nai = btracker_backend.nai_vests()
            AND h.source_op >= _start_op AND h.source_op < _end_op
        ) x
        WHERE x.op_type_id <> ALL (_read_ops)
          OR (x.op_type_id = _fill AND x.balance > x.previous_balance)
      ) AS other_vests
    FROM (
      SELECT DISTINCT m.account_id
      FROM recon_members m
      JOIN recon_diffs d ON d.witness_id = m.witness_id
      WHERE d.total <> d.change
    ) a;

  SELECT string_agg(format('%s: %s', e.reason, e.witnesses), '; ' ORDER BY e.reason)
  INTO _summary
  FROM (
    SELECT r.reason, format('%s (%s)', count(*), string_agg(r.name, ', ' ORDER BY r.name) FILTER (WHERE r.n <= 5)) AS witnesses
    FROM (
      SELECT x.reason, av.name, ROW_NUMBER() OVER (PARTITION BY x.reason ORDER BY av.name) AS n
      FROM (
        SELECT
          d.witness_id,
          CASE
            WHEN bool_or(f.proxy_chain) THEN 'proxy chain'
            WHEN bool_or(f.delayed_vests) THEN 'delayed VESTS'
            WHEN bool_or(f.other_vests) THEN 'other VESTS'
          END AS reason
        FROM recon_diffs d
        LEFT JOIN recon_members m ON m.witness_id = d.witness_id
        LEFT JOIN recon_flags f ON f.account_id = m.account_id
        WHERE d.total <> d.change
          AND d.witness_id <> ALL (_exact)
        GROUP BY d.witness_id
      ) x
      JOIN hafbe_app.accounts_view av ON av.id = x.witness_id
      WHERE x.reason IS NOT NULL
    ) r
    GROUP BY r.reason
  ) e;

  SELECT string_agg(format('%s total %s, votes changed by %s', COALESCE(av.name, d.witness_id::TEXT), d.total, d.change), '; ')
  INTO _failures
  FROM recon_diffs d
  LEFT JOIN hafbe_app.accounts_view av ON av.id = d.witness_id
  WHERE d.total <> d.change
    AND (
      d.witness_id = ANY (_exact)
      OR NOT EXISTS (
        SELECT 1
        FROM recon_members m
        JOIN recon_flags f ON f.account_id = m.account_id
        WHERE m.witness_id = d.witness_id
          AND (f.proxy_chain OR f.delayed_vests OR f.other_vests)
      )
    );

  IF _failures IS NOT NULL THEN
    RAISE EXCEPTION '%: witnesses whose total differs from the change of their votes outside the documented approximations: %', _label, _failures;
  END IF;
  IF (SELECT count(*) FROM recon_diffs d WHERE d.witness_id = ANY (_exact) AND d.total <> 0) <> cardinality(_exact) THEN
    RAISE EXCEPTION '%: the scenario''s witnesses are not all in the comparison', _label;
  END IF;
  RAISE NOTICE '%: % witnesses compared, % match exactly (the scenario''s % among them); differing by an approximation: %',
    _label, _compared, _exact_n, cardinality(_exact), COALESCE(_summary, 'none');
END
$$;

-- The stored breakdown, its start votes and state, as they were before a failing refresh.
CREATE TEMP TABLE saved_breakdown AS SELECT * FROM hafbe_app.witness_votes_change_by_cause WITH NO DATA;
CREATE TEMP TABLE saved_start AS SELECT * FROM hafbe_app.witness_votes_change_by_cause_start WITH NO DATA;
CREATE TEMP TABLE saved_state AS SELECT * FROM hafbe_app.witness_votes_change_by_cause_state WITH NO DATA;

CREATE FUNCTION pg_temp.expect_breakdown_kept(_case TEXT)
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
  IF EXISTS (
       (SELECT * FROM saved_breakdown EXCEPT ALL SELECT * FROM hafbe_app.witness_votes_change_by_cause)
       UNION ALL
       (SELECT * FROM hafbe_app.witness_votes_change_by_cause EXCEPT ALL SELECT * FROM saved_breakdown)
     )
     OR EXISTS (
       (SELECT * FROM saved_start EXCEPT ALL SELECT * FROM hafbe_app.witness_votes_change_by_cause_start)
       UNION ALL
       (SELECT * FROM hafbe_app.witness_votes_change_by_cause_start EXCEPT ALL SELECT * FROM saved_start)
     )
     OR (SELECT row(s.*)::TEXT FROM hafbe_app.witness_votes_change_by_cause_state s)
        IS DISTINCT FROM (SELECT row(s.*)::TEXT FROM saved_state s) THEN
    RAISE EXCEPTION '%: the previous breakdown was not kept', _case;
  END IF;
  RAISE NOTICE '%: contained, the previous breakdown (% rows) is in place', _case, (SELECT count(*) FROM saved_breakdown);
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
  _parts       TEXT[] := ARRAY['X', 'Y', 'Z', 'W', 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'K', 'L',
                               'P', 'Q', 'S', 'U', 'M', 'N', 'R0', 'R1', 'R2', 'R3', 'R4', 'T'];
  _exact       INT[];
  _picked      INT;
  _mismatches  INT;
  _state       hafbe_app.witness_votes_change_by_cause_state;
  _breakdown   JSON;
  _rank        INT;
  _moved       INT;
BEGIN
  IF _head IS NULL THEN
    RAISE EXCEPTION 'hafbe_app has processed no block: sync it first';
  END IF;
  INSERT INTO scenario_settings (write_ops, head) VALUES (_write_ops, _head);
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
      LIMIT 27
    ) av
  ) c ON c.n = r.n;
  GET DIAGNOSTICS _picked = ROW_COUNT;
  IF _picked <> cardinality(_parts) THEN
    RAISE EXCEPTION 'found % untouched accounts, the scenario needs %', _picked, cardinality(_parts);
  END IF;
  DELETE FROM account_withdraws w WHERE w.account IN (SELECT s.id FROM scenario_accounts s);
  _exact := ARRAY[pg_temp.account('X'), pg_temp.account('Z'), pg_temp.account('W')];
  IF _write_ops THEN
    _exact := _exact || pg_temp.account('Y');
  END IF;

  -- The prior state. X, Y, Z and W are registered witnesses, ranked with the others.
  INSERT INTO hafbe_app.current_witnesses (witness_id)
  SELECT pg_temp.account(w.part) FROM unnest(ARRAY['X', 'Y', 'Z', 'W']) AS w (part);
  PERFORM pg_temp.set_vests(p.part, p.vests, _other, pg_temp.next_op(_before))
  FROM (VALUES ('A', 980), ('B', 600), ('C', 250), ('D', 45), ('E', 200), ('F', 30), ('G', 70),
               ('H', 80), ('I', 400), ('K', 60), ('L', 90), ('P', 500), ('Q', 700), ('S', 300),
               ('U', 200), ('M', 120), ('N', 130), ('R0', 40), ('R1', 60), ('R2', 35), ('R3', 45),
               ('R4', 55), ('T', 15)) AS p (part, vests);
  PERFORM pg_temp.op_vote(_before, v.voter, v.witness, TRUE)
  FROM (VALUES ('A', 'X'), ('C', 'X'), ('H', 'X'), ('I', 'Y'), ('L', 'Y'), ('P', 'Z'), ('Q', 'W')) AS v (voter, witness);
  PERFORM pg_temp.op_proxy(_before, p.account, p.proxy)
  FROM (VALUES ('D', 'E'), ('E', 'A'), ('G', 'E'), ('K', 'A'), ('S', 'P'), ('M', 'P'), ('N', 'Q'),
               ('U', 'P'), ('R0', 'R1'), ('R1', 'R2'), ('R2', 'R3'), ('R3', 'R4'), ('R4', 'Q')) AS p (account, proxy);
  -- U switches from P to Q.
  PERFORM pg_temp.op_proxy(_before + 1, 'U', 'Q');
  PERFORM pg_temp.op_proxy_cleared(_before + 1, 'U', 'P');

  -- The window, one event per block. A's 15 delayed VESTS are delayed until t7.
  IF _write_ops THEN
    INSERT INTO account_withdraws (account, delayed_vests) VALUES (pg_temp.account('A'), 15);
  END IF;
  PERFORM pg_temp.set_vests('C', 290, _claim, pg_temp.next_op(_window + 1));
  PERFORM pg_temp.op_vote(_window + 2, 'B', 'X', TRUE);
  PERFORM pg_temp.set_vests('B', 500, _fill, pg_temp.next_op(_window + 3));
  -- An approval made before the window, removed in it.
  PERFORM pg_temp.op_vote(_window + 4, 'C', 'X', FALSE);
  PERFORM pg_temp.set_vests('C', 300, _claim, pg_temp.next_op(_window + 5));
  PERFORM pg_temp.set_vests('A', 1000, _producer, pg_temp.next_op(_window + 6));
  IF _write_ops THEN
    PERFORM pg_temp.next_op(_window + 7, 'delayed_voting_operation',
      jsonb_build_object('voter', pg_temp.account_name('A'), 'votes', 15));
    UPDATE account_withdraws SET delayed_vests = 0 WHERE account = pg_temp.account('A');
  END IF;
  PERFORM pg_temp.set_vests('D', 50, _claim, pg_temp.next_op(_window + 8));
  PERFORM pg_temp.op_proxy(_window + 9, 'F', 'E');
  PERFORM pg_temp.op_proxy(_window + 10, 'G', NULL);
  PERFORM pg_temp.op_proxy_cleared(_window + 10, 'G', 'E');
  IF _write_ops THEN
    PERFORM pg_temp.op_proxy(_window + 11, 'H', 'A');
    PERFORM pg_temp.op_voting_rights_lost(_window + 12, 'I', 'expired_account_notification_operation');
    PERFORM pg_temp.op_proxy_cleared(_window + 13, 'K', 'A');
    PERFORM pg_temp.op_voting_rights_lost(_window + 13, 'K', 'expired_account_notification_operation');
    PERFORM pg_temp.op_voting_rights_lost(_window + 14, 'L', 'declined_voting_rights_operation');
  END IF;
  PERFORM pg_temp.op_proxy(_window + 15, 'S', 'Q');
  PERFORM pg_temp.op_proxy_cleared(_window + 15, 'S', 'P');
  PERFORM pg_temp.set_vests('S', 310, _claim, pg_temp.next_op(_window + 16));
  PERFORM pg_temp.op_proxy(_window + 17, 'U', NULL);
  PERFORM pg_temp.op_proxy_cleared(_window + 17, 'U', 'Q');
  IF _write_ops THEN
    PERFORM pg_temp.op_proxy_cleared(_window + 18, 'M', 'P');
    PERFORM pg_temp.op_voting_rights_lost(_window + 18, 'M', 'expired_account_notification_operation');
    PERFORM pg_temp.op_proxy_cleared(_window + 19, 'N', 'Q');
    PERFORM pg_temp.op_voting_rights_lost(_window + 19, 'N', 'declined_voting_rights_operation');
  END IF;
  PERFORM pg_temp.set_vests('R1', 85, _claim, pg_temp.next_op(_window + 20));
  PERFORM pg_temp.set_vests('R0', 47, _claim, pg_temp.next_op(_window + 21));
  PERFORM pg_temp.op_proxy(_window + 22, 'T', 'R2');

  IF _write_ops THEN
    PERFORM pg_temp.expect('the window', _window, 'X', '{
      "votes_cast": [600, 1], "power_down": [-100, 1], "votes_removed": [-290, 1],
      "claimed_reward": [45, 2], "producer_reward": [20, 1], "power_up": [15, 1],
      "proxy": [-40, 2], "expired": [-60, 1], "total": [190, 4]}');
    PERFORM pg_temp.expect('the window', _window, 'Y', '{
      "expired": [-400, 1], "declined": [-90, 1], "total": [-490, 2]}');
    PERFORM pg_temp.expect('the window', _window, 'Z', '{
      "proxy": [-300, 1], "expired": [-120, 1], "total": [-420, 1]}');
    PERFORM pg_temp.expect('the window', _window, 'W', '{
      "proxy": [115, 1], "claimed_reward": [35, 1], "declined": [-130, 1], "total": [20, 1]}');
  ELSE
    RAISE NOTICE 'SKIPPED power_up (t7), the proxy cascade (t11), expired (t12, t13, t18) and declined (t14, t19): % may not write hafd.operations', current_user;
    PERFORM pg_temp.expect('the window', _window, 'X', '{
      "votes_cast": [600, 1], "power_down": [-100, 1], "votes_removed": [-290, 1],
      "claimed_reward": [45, 2], "producer_reward": [20, 1],
      "proxy": [-40, 1], "total": [235, 3]}');
    PERFORM pg_temp.expect('the window', _window, 'Y', '{}');
    PERFORM pg_temp.expect('the window', _window, 'Z', '{
      "proxy": [-300, 1], "total": [-300, 1]}');
    PERFORM pg_temp.expect('the window', _window, 'W', '{
      "proxy": [115, 1], "claimed_reward": [35, 1], "total": [150, 1]}');
  END IF;

  -- A window starting after the events sees none of them.
  PERFORM pg_temp.expect('a window after the events', _window + 30, 'X', '{}');
  PERFORM pg_temp.expect('a window after the events', _window + 30, 'W', '{}');

  -- Every witness's total against the change of its votes.
  CREATE TEMP TABLE recon_totals AS
    SELECT c.witness_id, c.vests
    FROM hafbe_app.witness_votes_change_by_cause_of(_window) c
    WHERE c.cause = 'total';
  PERFORM pg_temp.reconcile('reconciliation of the scenario''s window', _window, _exact);

  -- The refresh over the synced chain and the scenario, with the witness vote cache
  -- holding the same block as single_processing() leaves it.
  PERFORM hafbe_app.process_witness_votes_cache();
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
  SELECT * INTO _state FROM hafbe_app.witness_votes_change_by_cause_state;
  IF _state.as_of_block IS DISTINCT FROM _head
     OR _state.week_first_block IS DISTINCT FROM _week_start
     OR _state.today_first_block IS DISTINCT FROM hafbe_app.witness_votes_change_today_start(_head) THEN
    RAISE EXCEPTION 'refresh: the state % does not hold block % and its windows', _state, _head;
  END IF;
  -- Each window starts at its first block after the boundary, not the one before it.
  IF (SELECT b.created_at FROM hive.blocks_view b WHERE b.num = _week_start - 1)
       >= (SELECT b.created_at FROM hive.blocks_view b WHERE b.num = _head) - INTERVAL '7 days'
     OR (SELECT b.created_at FROM hive.blocks_view b WHERE b.num = _week_start)
       < (SELECT b.created_at FROM hive.blocks_view b WHERE b.num = _head) - INTERVAL '7 days' THEN
    RAISE EXCEPTION 'refresh: the 7-day window does not start at the first block of the last 7 days (%)', _week_start;
  END IF;
  RAISE NOTICE 'refresh: % rows, every total is the sum of its causes; windows from block % (7d) and % (today)',
    (SELECT count(*) FROM hafbe_app.witness_votes_change_by_cause), _state.week_first_block, _state.today_first_block;

  DROP TABLE recon_totals;
  CREATE TEMP TABLE recon_totals AS
    SELECT c.witness_id, c.vests
    FROM hafbe_app.witness_votes_change_by_cause c
    WHERE c.time_window = '7d' AND c.cause = 'total';
  PERFORM pg_temp.reconcile('reconciliation of the stored 7d window', _state.week_first_block, _exact);
  DROP TABLE recon_totals;
  CREATE TEMP TABLE recon_totals AS
    SELECT c.witness_id, c.vests
    FROM hafbe_app.witness_votes_change_by_cause c
    WHERE c.time_window = 'today' AND c.cause = 'total';
  PERFORM pg_temp.reconcile('reconciliation of the stored today window', _state.today_first_block, ARRAY[]::INT[]);

  -- rank_start ranks every current witness, like rank, by its votes and voters at
  -- the window's start of the refresh's own block: the cache's then minus the
  -- window's total and net approvals.
  CREATE TEMP TABLE rank_keys AS
    SELECT
      cw.witness_id,
      w.time_window,
      s.votes,
      s.rank_start,
      a.rank,
      COALESCE(wv.votes, 0) - COALESCE(t.vests, 0) AS start_votes,
      COALESCE(wv.voters_num, 0) - COALESCE((
        SELECT SUM(CASE WHEN h.approve THEN 1 ELSE -1 END)
        FROM hafbe_app.witness_votes_history h
        WHERE h.witness_id = cw.witness_id
          AND h.source_op >= hafd.operation_id(CASE w.time_window WHEN 'today' THEN _state.today_first_block ELSE _state.week_first_block END, 0)
      ), 0) AS start_voters,
      COALESCE(wv.votes, 0) AS votes_now,
      COALESCE(wv.voters_num, 0) AS voters_now
    FROM hafbe_app.current_witnesses cw
    CROSS JOIN (VALUES ('today'), ('7d')) AS w (time_window)
    JOIN hafbe_app.witness_rank_cache a ON a.witness_id = cw.witness_id
    LEFT JOIN hafbe_app.witness_votes_change_by_cause_start s
      ON s.witness_id = cw.witness_id AND s.time_window = w.time_window
    LEFT JOIN hafbe_app.witness_votes_cache wv ON wv.witness_id = cw.witness_id
    LEFT JOIN hafbe_app.witness_votes_change_by_cause t
      ON t.witness_id = cw.witness_id AND t.time_window = w.time_window AND t.cause = 'total';
  SELECT count(*)
  INTO _mismatches
  FROM (
    SELECT
      k.votes,
      k.rank_start,
      k.start_votes,
      (ROW_NUMBER() OVER (PARTITION BY k.time_window ORDER BY k.start_votes DESC, k.start_voters DESC, k.witness_id DESC))::INT AS expected_rank
    FROM rank_keys k
  ) r
  WHERE (r.votes, r.rank_start) IS DISTINCT FROM (r.start_votes, r.expected_rank);
  _mismatches := _mismatches + (
    SELECT count(*)
    FROM hafbe_app.witness_votes_change_by_cause_start s
    WHERE NOT EXISTS (SELECT 1 FROM hafbe_app.current_witnesses cw WHERE cw.witness_id = s.witness_id)
  );
  IF _mismatches <> 0 THEN
    RAISE EXCEPTION 'rank_start: % rows do not rank the witnesses at the window start of block %', _mismatches, _head;
  END IF;
  -- A witness the window did not move keeps its place: its rank_start differs from
  -- its rank only by the moved witnesses that passed it, either way. With none, a
  -- witness with no votes, before and after, has rank_start = rank.
  SELECT count(*)
  INTO _mismatches
  FROM rank_keys k
  WHERE (k.start_votes, k.start_voters) = (k.votes_now, k.voters_now)
    AND k.rank_start - k.rank IS DISTINCT FROM (
      SELECT
        count(*) FILTER (WHERE (m.start_votes, m.start_voters, m.witness_id) > (k.votes_now, k.voters_now, k.witness_id))
        - count(*) FILTER (WHERE (m.votes_now, m.voters_now, m.witness_id) > (k.votes_now, k.voters_now, k.witness_id))
      FROM rank_keys m
      WHERE m.time_window = k.time_window
        AND (m.start_votes, m.start_voters) <> (m.votes_now, m.voters_now)
    );
  IF _mismatches <> 0 THEN
    RAISE EXCEPTION 'rank_start: % unmoved witnesses are not at their rank shifted by the moved ones', _mismatches;
  END IF;
  SELECT count(*)
  INTO _mismatches
  FROM rank_keys k
  WHERE k.votes_now = 0 AND k.start_votes = 0 AND k.voters_now = 0 AND k.start_voters = 0
    AND k.rank_start = k.rank;
  IF _mismatches = 0 THEN
    RAISE EXCEPTION 'rank_start: no witness without votes has rank_start = rank';
  END IF;
  RAISE NOTICE 'rank_start: % rows rank the witnesses like rank; % witness windows without votes have rank_start = rank',
    (SELECT count(*) FROM rank_keys), _mismatches;
  IF (SELECT s.votes FROM hafbe_app.witness_votes_change_by_cause_start s
      WHERE s.witness_id = pg_temp.account('X') AND s.time_window = '7d')
     IS DISTINCT FROM (CASE WHEN _write_ops THEN 1670 ELSE 1685 END) THEN
    RAISE EXCEPTION 'rank_start: X''s votes at the 7-day window start are not the scenario''s';
  END IF;

  -- After the refresh the cache moves on with later blocks; rank_start stays with
  -- the refresh's block. X jumps to the top of the cache.
  SELECT (b.votes_change_breakdown -> '7d' ->> 'rank_start')::INT INTO _rank
  FROM hafbe_backend.witness_votes_change_breakdown(ARRAY[pg_temp.account('X')]) b;
  UPDATE hafbe_app.witness_votes_cache SET votes = votes + (SELECT max(v.votes) FROM hafbe_app.witness_votes_cache v)
  WHERE witness_id = pg_temp.account('X');
  SELECT (b.votes_change_breakdown -> '7d' ->> 'rank_start')::INT INTO _moved
  FROM hafbe_backend.witness_votes_change_breakdown(ARRAY[pg_temp.account('X')]) b;
  IF _rank IS NULL OR _moved IS DISTINCT FROM _rank
     OR _rank IS DISTINCT FROM (SELECT s.rank_start FROM hafbe_app.witness_votes_change_by_cause_start s
                                WHERE s.witness_id = pg_temp.account('X') AND s.time_window = '7d') THEN
    RAISE EXCEPTION 'rank_start: X ranked % at the refresh and % after the cache moved', _rank, _moved;
  END IF;
  RAISE NOTICE 'rank_start: X ranks % at the 7-day window start of block %, also after the cache moved', _rank, _head;

  -- The 7-day window reaches back past the scenario's window: X's breakdown holds it.
  SELECT b.votes_change_breakdown INTO _breakdown
  FROM hafbe_backend.witness_votes_change_breakdown(ARRAY[pg_temp.account('X')]) b;
  IF (_breakdown ->> 'as_of_block')::INT IS DISTINCT FROM _head
     OR _breakdown -> '7d' ->> 'total' IS DISTINCT FROM (CASE WHEN _write_ops THEN '190' ELSE '235' END)
     OR _breakdown -> '7d' ->> 'votes_cast' IS DISTINCT FROM '600'
     OR _breakdown -> '7d' ->> 'power_down' IS DISTINCT FROM '-100'
     OR (SELECT count(*) FROM json_object_keys(_breakdown -> '7d')) <> 12
     OR (SELECT count(*) FROM json_object_keys(_breakdown -> 'today')) <> 12 THEN
    RAISE EXCEPTION 'votes_change_breakdown of X is not the scenario: %', _breakdown;
  END IF;
  RAISE NOTICE 'votes_change_breakdown: %', _breakdown;

  INSERT INTO saved_breakdown SELECT * FROM hafbe_app.witness_votes_change_by_cause;
  INSERT INTO saved_start SELECT * FROM hafbe_app.witness_votes_change_by_cause_start;
  INSERT INTO saved_state SELECT * FROM hafbe_app.witness_votes_change_by_cause_state;
END
$$;

-- The today window is votes_daily_change's, also for a block shortly after 00:00 UTC
-- in a session TimeZone whose date is still the previous one: it starts at the first
-- block of the block's UTC day.
DO $$
DECLARE
  _head  INT := (SELECT c.current_block_num FROM hafd.contexts c WHERE c.name = 'hafbe_app');
  _day   TIMESTAMP := (SELECT date_trunc('day', b.created_at) FROM hive.blocks_view b WHERE b.num = _head);
  _first INT;
  _late  INT;
  _utc   INT;
  _ny    INT;
BEGIN
  SELECT b.num INTO _first FROM hive.blocks_view b WHERE b.created_at >= _day ORDER BY b.created_at LIMIT 1;
  _late := LEAST(_first + 10, _head);
  SET LOCAL TIME ZONE 'UTC';
  _utc := hafbe_app.witness_votes_change_today_start(_late);
  SET LOCAL TIME ZONE 'America/New_York';
  _ny := hafbe_app.witness_votes_change_today_start(_late);
  RESET TIME ZONE;
  IF _utc IS DISTINCT FROM _first OR _ny IS DISTINCT FROM _first
     OR hafbe_app.witness_votes_cache_window_start(_late) IS DISTINCT FROM _first THEN
    RAISE EXCEPTION 'today window: block % starts it at block % in UTC and % in America/New_York, votes_daily_change at %, not at its day''s first block %',
      _late, _utc, _ny, hafbe_app.witness_votes_cache_window_start(_late), _first;
  END IF;
  RAISE NOTICE 'today window: block % starts it at block % (00:00 UTC %) in UTC and America/New_York, as votes_daily_change',
    _late, _first, _day;
END
$$;

-- A refresh that fails. process_witness_votes_change_by_cause() refreshes for a block
-- below the last refreshed one (a fork); the 7-day window's start is replaced by a
-- function that fails, which the rollback below restores. Each case starts with no
-- failure recorded and checks that its own failure was.
SELECT s.as_of_block AS as_of_block FROM hafbe_app.witness_votes_change_by_cause_state s \gset

CREATE FUNCTION pg_temp.expect_failed_at(_case TEXT, _block INT)
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
  IF current_setting('hafbe_app.witness_votes_change_by_cause_failed_block', TRUE) IS DISTINCT FROM _block::TEXT THEN
    RAISE EXCEPTION '%: no failed refresh recorded at block % (recorded: %)', _case, _block,
      current_setting('hafbe_app.witness_votes_change_by_cause_failed_block', TRUE);
  END IF;
  PERFORM set_config('hafbe_app.witness_votes_change_by_cause_failed_block', '', FALSE);
END
$$;

SET ROLE hafbe_owner;
CREATE OR REPLACE FUNCTION hafbe_app.witness_votes_change_week_start(_block INT)
RETURNS INT
LANGUAGE sql STABLE
AS $$
  SELECT 0 FROM pg_sleep(60)
$$;
RESET ROLE;
SET LOCAL statement_timeout = '2s';
SELECT hafbe_app.process_witness_votes_change_by_cause(:as_of_block - 1);
SET LOCAL statement_timeout = 0;
SELECT pg_temp.expect_failed_at('a refresh past the statement timeout', :as_of_block - 1);
SELECT pg_temp.expect_breakdown_kept('a refresh past the statement timeout');

SET ROLE hafbe_owner;
CREATE OR REPLACE FUNCTION hafbe_app.witness_votes_change_week_start(_block INT)
RETURNS INT
LANGUAGE plpgsql STABLE
AS $$
BEGIN
  RAISE EXCEPTION 'a failure of the refresh';
END
$$;
RESET ROLE;
SELECT hafbe_app.process_witness_votes_change_by_cause(:as_of_block - 1);
SELECT pg_temp.expect_failed_at('a refresh that raises', :as_of_block - 1);
SELECT pg_temp.expect_breakdown_kept('a refresh that raises');

-- A cancel by request (pg_cancel_backend) during the refresh is a failure of the
-- refresh like the others: the refresher session goes on (#211).
SET ROLE hafbe_owner;
CREATE OR REPLACE FUNCTION hafbe_app.witness_votes_change_week_start(_block INT)
RETURNS INT
LANGUAGE plpgsql VOLATILE
AS $$
BEGIN
  PERFORM pg_cancel_backend(pg_backend_pid());
  PERFORM pg_sleep(5);
  RETURN 0;
END
$$;
RESET ROLE;

SELECT hafbe_app.process_witness_votes_change_by_cause(:as_of_block - 1);
SELECT pg_temp.expect_failed_at('a cancel by request', :as_of_block - 1);
SELECT pg_temp.expect_breakdown_kept('a cancel by request');

-- Nothing is due at the last refresh's own block: the refresher checks every few
-- seconds, and a stalled chain must not refresh on each check.
SELECT hafbe_app.process_witness_votes_change_by_cause(:as_of_block);
SELECT pg_temp.expect_breakdown_kept('a check at the last refresh''s block');
-- The failing 7-day window start is still in place: an attempt would have recorded a failure
DO $$
BEGIN
  IF COALESCE(current_setting('hafbe_app.witness_votes_change_by_cause_failed_block', TRUE), '') <> '' THEN
    RAISE EXCEPTION 'a check at the last refresh''s block attempted a refresh (failure recorded at block %)',
      current_setting('hafbe_app.witness_votes_change_by_cause_failed_block', TRUE);
  END IF;
  RAISE NOTICE 'a check at the last refresh''s block: no refresh attempted';
END
$$;

-- A failed refresh is attempted again 100 blocks after the failure, not on each block
-- in between. With no state row every block asks for a refresh; the failing 7-day
-- window start counts the attempts.
CREATE TEMP SEQUENCE refresh_attempts;

CREATE FUNCTION pg_temp.expect_attempts(_case TEXT, _expected INT)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
  _attempts INT := (SELECT CASE WHEN a.is_called THEN a.last_value ELSE 0 END FROM refresh_attempts a);
BEGIN
  IF _attempts <> _expected THEN
    RAISE EXCEPTION '%: % refresh attempts, expected %', _case, _attempts, _expected;
  END IF;
  RAISE NOTICE '%: % refresh attempts', _case, _attempts;
END
$$;

SET ROLE hafbe_owner;
CREATE OR REPLACE FUNCTION hafbe_app.witness_votes_change_week_start(_block INT)
RETURNS INT
LANGUAGE plpgsql VOLATILE
AS $$
BEGIN
  PERFORM nextval('refresh_attempts');
  RAISE EXCEPTION 'a failure of the refresh';
END
$$;
DELETE FROM hafbe_app.witness_votes_change_by_cause_state;
RESET ROLE;

-- A refresh failed at as_of_block
SELECT set_config('hafbe_app.witness_votes_change_by_cause_failed_block', :'as_of_block', FALSE);
SELECT hafbe_app.process_witness_votes_change_by_cause(:as_of_block + 1);
SELECT hafbe_app.process_witness_votes_change_by_cause(b) FROM generate_series(:as_of_block + 2, :as_of_block + 99) b;
SELECT pg_temp.expect_attempts('the 99 blocks after a failed refresh', 0);
SELECT hafbe_app.process_witness_votes_change_by_cause(:as_of_block + 100);
SELECT pg_temp.expect_attempts('100 blocks after the failed refresh', 1);
SELECT hafbe_app.process_witness_votes_change_by_cause(:as_of_block + 101);
SELECT pg_temp.expect_attempts('the block after that failed again', 1);
-- A chain stalled at the failed block: the refresher's next checks find the same block
SELECT hafbe_app.process_witness_votes_change_by_cause(:as_of_block + 100);
SELECT pg_temp.expect_attempts('the failed block checked again (a stalled chain)', 1);

-- A new UTC day refreshes at its first block, not at the next 100th: a block whose
-- today window is not the stored one asks for a refresh, one whose window is does not.
SELECT set_config('hafbe_app.witness_votes_change_by_cause_failed_block', '', FALSE);
SELECT :as_of_block - 1 - ((:as_of_block - 1) % 100 = 0)::INT AS day_block \gset
SET ROLE hafbe_owner;
INSERT INTO hafbe_app.witness_votes_change_by_cause_state (as_of_block, today_first_block, week_first_block)
VALUES (:day_block - 1, hafbe_app.witness_votes_change_today_start(:day_block), 0);
RESET ROLE;
SELECT hafbe_app.process_witness_votes_change_by_cause(:day_block);
SELECT pg_temp.expect_attempts('a block of the stored today window', 1);
SET ROLE hafbe_owner;
UPDATE hafbe_app.witness_votes_change_by_cause_state SET today_first_block = today_first_block - 1;
RESET ROLE;
SELECT set_config('hafbe_app.witness_votes_change_by_cause_failed_block', '', FALSE);
SELECT hafbe_app.process_witness_votes_change_by_cause(:day_block);
SELECT pg_temp.expect_attempts('the first block of a new UTC day', 2);

-- Due 100 blocks after the last refresh, whatever the block number: the refresher
-- checks every few seconds, so it would rarely see a block that is a multiple of 100.
-- The last refresh is at block x with x % 100 = 1, in one UTC day with x + 100: x + 99
-- (a multiple of 100) is not due, x + 100 is.
SELECT set_config('hafbe_app.witness_votes_change_by_cause_failed_block', '', FALSE);
SELECT x
FROM generate_series(((:as_of_block - 200) / 100) * 100 + 1, 1, -100) x
WHERE hafbe_app.witness_votes_change_today_start(x) = hafbe_app.witness_votes_change_today_start(x + 100)
LIMIT 1 \gset
SET ROLE hafbe_owner;
UPDATE hafbe_app.witness_votes_change_by_cause_state
SET as_of_block = :x, today_first_block = hafbe_app.witness_votes_change_today_start(:x);
RESET ROLE;
SELECT hafbe_app.process_witness_votes_change_by_cause(:x + 99);
SELECT pg_temp.expect_attempts('99 blocks after the last refresh, a multiple of 100', 2);
SELECT hafbe_app.process_witness_votes_change_by_cause(:x + 100);
SELECT pg_temp.expect_attempts('100 blocks after the last refresh', 3);

ROLLBACK;
