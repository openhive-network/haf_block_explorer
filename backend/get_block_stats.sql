CREATE OR REPLACE FUNCTION hafbe_backend.get_head_block_num()
RETURNS INT
LANGUAGE 'plpgsql'
AS
$$
BEGIN
  RETURN num FROM hive.blocks_view ORDER BY num DESC LIMIT 1;
END
$$
;

CREATE OR REPLACE FUNCTION hafbe_backend.get_set_of_block_data(_block_num INT)
RETURNS SETOF hafbe_types.block
AS
$function$
BEGIN
  RETURN QUERY SELECT
    hbv.num,
    encode(hbv.hash, 'hex'),
    hbv.created_at::TEXT,
    hav.name::TEXT,
    hbv.signing_key
  FROM hive.accounts_view hav
  JOIN (
    SELECT num, hash, created_at, producer_account_id, signing_key
    FROM hive.blocks_view
    WHERE num = _block_num
    LIMIT 1
  ) hbv ON hbv.producer_account_id = hav.id;
END
$function$
LANGUAGE 'plpgsql' STABLE
SET JIT=OFF
SET join_collapse_limit=16
SET from_collapse_limit=16
;


CREATE OR REPLACE FUNCTION hafbe_backend.get_todays_date()
RETURNS DATE
LANGUAGE 'plpgsql'
AS
$$
DECLARE
  __today DATE;
BEGIN
  IF (
    SELECT timestamp::DATE FROM hafbe_app.witness_votes_history ORDER BY timestamp DESC LIMIT 1
  ) != 'today'::DATE THEN
    __today = NULL;
  ELSE
    __today = 'today'::DATE;
  END IF;
  RETURN __today;
END
$$
;

CREATE OR REPLACE FUNCTION hafbe_backend.vests_to_hive_power(VARIADIC vests_value NUMERIC[])
RETURNS SETOF FLOAT
LANGUAGE 'plpgsql'
AS
$$
BEGIN
  RETURN QUERY SELECT
    (unnest(vests_value) * total_vesting_fund_hive / total_vesting_shares)::FLOAT
  FROM hive.blocks
  ORDER BY num DESC
  LIMIT 1;
END
$$
;
