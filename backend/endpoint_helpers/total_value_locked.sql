CREATE OR REPLACE FUNCTION hafbe_backend.get_total_value_locked()
RETURNS hafbe_types.total_value_locked
LANGUAGE plpgsql
STABLE
SET JIT = OFF
SET join_collapse_limit = 16
SET from_collapse_limit = 16
AS
$$
DECLARE
  -- NAI constants
  _NAI_VESTS CONSTANT INT := 37;  -- VESTS
  _NAI_HBD   CONSTANT INT := 13;  -- HBD
  _NAI_HIVE  CONSTANT INT := 21;  -- HIVE

  _head_block     INT;

  _sum_vests     BIGINT;
  _sum_sav_hive  BIGINT;
  _sum_sav_hbd   BIGINT;
BEGIN
  -- Head block number
  SELECT bv.num
  INTO   _head_block
  FROM   hive.blocks_view bv
  ORDER  BY bv.num DESC
  LIMIT  1;

  IF _head_block IS NULL THEN
    RAISE EXCEPTION 'No blocks in database';
  END IF;

  -- VESTS from hafbe_bal.current_account_balances
  SELECT COALESCE(SUM(cab.balance), 0)::BIGINT
  INTO   _sum_vests
  FROM   hafbe_bal.current_account_balances cab
  WHERE  cab.nai = _NAI_VESTS;

  -- Savings HIVE & HBD from hafbe_bal.account_savings
  SELECT
    COALESCE(SUM(CASE WHEN asv.nai = _NAI_HIVE THEN asv.balance  ELSE 0 END), 0)::BIGINT,
    COALESCE(SUM(CASE WHEN asv.nai = _NAI_HBD  THEN asv.balance  ELSE 0 END), 0)::BIGINT
  INTO
    _sum_sav_hive,
    _sum_sav_hbd
  FROM hafbe_bal.account_savings asv;

  RETURN (
    _head_block,
    _sum_vests,
    _sum_sav_hive,
    _sum_sav_hbd
  )::hafbe_types.total_value_locked;
END
$$;
