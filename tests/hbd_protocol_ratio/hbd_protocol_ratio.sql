-- The protocol HBD debt ratio of /hbd/status (debt_ratio_protocol_pct, #153).
--
-- 1. hafbe_backend.hbd_protocol_debt_ratio_pct() against hived's own computation
--    (database::calculate_HBD_percent: integer basis points, rounded since HF21) on real
--    mainnet block values, and its edge cases.
-- 2. The endpoint on the synced chain, which ends before HF24: the protocol ratio equals the
--    gross one in every period.
-- 3. The endpoint with an HF24 and a treasury (hive.fund) faked mid-chain: periods sampled
--    before HF24 keep the gross ratio, later ones subtract the treasury's liquid HBD as of
--    their sampled block (its last change at or before it).
-- Everything is rolled back.

\set ON_ERROR_STOP on
BEGIN;
SET LOCAL search_path TO hafbe_endpoints, hafbe_bal, reptracker_app, public;

-- ---------------------------------------------------------------- 1. the formula
DO $$
DECLARE
  -- block, hbd_supply, hive_supply, virtual_supply, treasury liquid HBD, expected percent
  _c RECORD;
  _pct NUMERIC;
  _hbd_in_hive NUMERIC;
  _remaining_value BIGINT;
  _chain_bp BIGINT;
BEGIN
  FOR _c IN SELECT * FROM (VALUES
      (109332923, 32115659745::BIGINT, 580016298657::BIGINT, 1326892106680::BIGINT, 23188597640::BIGINT, 26.359),
      (111000000, 31941076895, 592365042363, 1231186580263, 23219575663, 22.748),
      ( 47797681,  4618388975, 371986219334,  401402709620,   566914272,  6.487)
    ) AS v(block, hbd, hive, virt, treasury, expected)
  LOOP
    _pct := hafbe_backend.hbd_protocol_debt_ratio_pct(_c.hbd, _c.hive, _c.virt, _c.treasury, TRUE);
    ASSERT _pct = _c.expected, format('block %s: protocol ratio %s, want %s', _c.block, _pct, _c.expected);

    -- hived: the remaining HBD valued in HIVE (integer), then
    -- (hbd_as_hive * 10000 + virtual_supply / 2) / virtual_supply with the recomputed supply
    _hbd_in_hive := _c.virt - _c.hive;
    _remaining_value := floor(_hbd_in_hive * (_c.hbd - _c.treasury) / _c.hbd);
    _chain_bp := (_remaining_value * 10000 + (_remaining_value + _c.hive) / 2) / (_remaining_value + _c.hive);
    ASSERT abs(_pct - _chain_bp / 100.0) <= 0.005,
      format('block %s: protocol ratio %s is not within the 0.01%% step of the chain''s %s bp', _c.block, _pct, _chain_bp);

    -- before HF24 it is the gross share
    ASSERT hafbe_backend.hbd_protocol_debt_ratio_pct(_c.hbd, _c.hive, _c.virt, _c.treasury, FALSE)
           = ROUND(100::NUMERIC * (_c.virt - _c.hive) / _c.virt, 3),
      format('block %s: before HF24 the protocol ratio must equal the gross one', _c.block);
  END LOOP;

  -- a treasury holding all HBD (or more) leaves nothing: 0, as in hived
  ASSERT hafbe_backend.hbd_protocol_debt_ratio_pct(1000, 5000, 6000, 1000, TRUE) = 0, 'treasury = HBD supply';
  ASSERT hafbe_backend.hbd_protocol_debt_ratio_pct(1000, 5000, 6000, 2000, TRUE) = 0, 'treasury > HBD supply';
  -- no treasury balance: the gross share
  ASSERT hafbe_backend.hbd_protocol_debt_ratio_pct(1000, 5000, 6000, NULL, TRUE) = 16.667, 'no treasury row';
  -- no price feed yet (virtual_supply = hive_supply): 0, not a division error
  ASSERT hafbe_backend.hbd_protocol_debt_ratio_pct(1000, 5000, 5000, 400, TRUE) = 0, 'no feed';
  -- nothing to divide: NULL, like the gross column
  ASSERT hafbe_backend.hbd_protocol_debt_ratio_pct(0, 0, 0, 0, TRUE) IS NULL, 'empty chain, after HF24';
  ASSERT hafbe_backend.hbd_protocol_debt_ratio_pct(0, 0, 0, NULL, FALSE) IS NULL, 'empty chain, before HF24';
  -- half the HBD in the treasury: 1000 HBD worth 1000 HIVE next to 5000 HIVE -> 500 / 5500
  ASSERT hafbe_backend.hbd_protocol_debt_ratio_pct(1000, 5000, 6000, 500, TRUE) = 9.091, 'half in the treasury';

  RAISE NOTICE 'hbd_protocol_ratio: the formula matches hived on real blocks and its edge cases';
END
$$;

-- ---------------------------------------------------------------- 2. the synced chain (no HF24)
DO $$
DECLARE
  _rows INT := 0;
  _r RECORD;
BEGIN
  IF EXISTS (SELECT 1 FROM hafbe_app.applied_hardforks_view WHERE hardfork_num = 24) THEN
    RAISE NOTICE 'hbd_protocol_ratio: the synced chain has HF24; step 2 skipped';
    RETURN;
  END IF;
  FOR _r IN SELECT * FROM hafbe_endpoints.get_hbd_status('daily', 'asc') LOOP
    ASSERT _r.debt_ratio_protocol_pct IS NOT DISTINCT FROM _r.debt_ratio_gross_pct,
      format('%s: before HF24 protocol %s must equal gross %s', _r.period, _r.debt_ratio_protocol_pct, _r.debt_ratio_gross_pct);
    _rows := _rows + 1;
  END LOOP;
  ASSERT _rows > 0, 'get_hbd_status returned no periods';
  RAISE NOTICE 'hbd_protocol_ratio: % daily periods before HF24 report the gross ratio', _rows;
END
$$;

-- ---------------------------------------------------------------- 3. HF24 and a treasury, faked
-- HF24 at block 4,000,000 and hive.fund with 1,000 HBD from that block, 2,000 HBD from block
-- 4,500,000 (both well below the HBD supply there).
CREATE TEMP TABLE t_fake ON COMMIT DROP AS
SELECT 4000000 AS hf24, 4500000 AS second_change, 1000000::BIGINT AS t1, 2000000::BIGINT AS t2,
       (SELECT MAX(id) + 1 FROM hafd.accounts) AS fund;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM hafbe_app.applied_hardforks_view WHERE hardfork_num = 24)
     OR (SELECT hafbe_backend.get_hafbe_head_block()) < 4600000 THEN
    RAISE EXCEPTION 'hbd_protocol_ratio: step 3 needs a chain synced past block 4,600,000 without HF24';
  END IF;
END
$$;

INSERT INTO hafd.applied_hardforks (hardfork_num, block_num, hardfork_vop_id)
SELECT 24, f.hf24, (SELECT MIN(o.id) FROM hafd.operations o
                    WHERE o.id BETWEEN (f.hf24::BIGINT << 32) AND (((f.hf24 + 1)::BIGINT << 32) - 1))
FROM t_fake f;
INSERT INTO hafd.accounts (id, name, block_num) SELECT f.fund, 'hive.fund', f.hf24 FROM t_fake f;
INSERT INTO account_balance_history (account, nai, op_type_id, balance, balance_seq_no, source_op)
SELECT f.fund, btracker_backend.nai_hbd(), 0, v.balance, v.seq, (v.block::BIGINT << 32)
FROM t_fake f, LATERAL (VALUES (1, f.hf24, f.t1), (2, f.second_change, f.t2)) AS v(seq, block, balance);

DO $$
DECLARE
  f RECORD;
  _r RECORD;
  _treasury BIGINT;
  _want NUMERIC;
  _before INT := 0;
  _first INT := 0;
  _second INT := 0;
BEGIN
  SELECT * INTO f FROM t_fake;
  ASSERT (SELECT block_num FROM hafbe_app.applied_hardforks_view WHERE hardfork_num = 24) = f.hf24,
    'the faked HF24 is not visible to hafbe_app';

  FOR _r IN
    SELECT s.*, ab.last_block_num, b.current_hbd_supply, b.current_supply, b.virtual_supply
    FROM hafbe_endpoints.get_hbd_status('daily', 'asc') s
    JOIN hafbe_backend.get_aggregation_blocks('daily', 'asc', NULL, NULL, hafbe_backend.get_hafbe_head_block()) ab
      ON ab.date = s.period
    JOIN hafbe_app.blocks_view b ON b.num = ab.last_block_num
  LOOP
    IF _r.last_block_num < f.hf24 THEN
      ASSERT _r.debt_ratio_protocol_pct IS NOT DISTINCT FROM _r.debt_ratio_gross_pct,
        format('%s (block %s, before HF24): protocol %s, gross %s', _r.period, _r.last_block_num,
               _r.debt_ratio_protocol_pct, _r.debt_ratio_gross_pct);
      _before := _before + 1;
      CONTINUE;
    END IF;
    _treasury := CASE WHEN _r.last_block_num >= f.second_change THEN f.t2 ELSE f.t1 END;
    _want := hafbe_backend.hbd_protocol_debt_ratio_pct(_r.current_hbd_supply, _r.current_supply,
                                                       _r.virtual_supply, _treasury, TRUE);
    ASSERT _r.debt_ratio_protocol_pct = _want,
      format('%s (block %s): protocol %s, want %s with treasury %s', _r.period, _r.last_block_num,
             _r.debt_ratio_protocol_pct, _want, _treasury);
    ASSERT _r.debt_ratio_protocol_pct < _r.debt_ratio_gross_pct,
      format('%s (block %s): protocol %s not below gross %s', _r.period, _r.last_block_num,
             _r.debt_ratio_protocol_pct, _r.debt_ratio_gross_pct);
    IF _treasury = f.t1 THEN _first := _first + 1; ELSE _second := _second + 1; END IF;
  END LOOP;

  ASSERT _before > 0 AND _first > 0 AND _second > 0,
    format('periods before HF24 / with the first / with the second treasury balance: %s / %s / %s',
           _before, _first, _second);
  RAISE NOTICE 'hbd_protocol_ratio: with HF24 faked at block %: % periods gross before it, % and % with the treasury subtracted',
    f.hf24, _before, _first, _second;
END
$$;

ROLLBACK;
