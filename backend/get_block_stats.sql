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
RETURNS DATE STABLE
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

CREATE OR REPLACE FUNCTION hafbe_backend.get_block(_timestamp TIMESTAMP)
RETURNS JSONB
LANGUAGE 'plpgsql' STABLE
AS
$$
BEGIN

  RETURN
    jsonb_build_object(
      'num', o.num,
      'hash', o.hash,
      'prev', o.prev,
      'producer_account_id',  o.producer_account_id,
      'transaction_merkle_root', o.transaction_merkle_root,
      'extensions', o.extensions,
      'witness_signature', o.witness_signature,
      'signing_key', o.signing_key,
      'hbd_interest_rate', o.hbd_interest_rate,
      'total_vesting_fund_hive', o.total_vesting_fund_hive,
      'total_vesting_shares', o.total_vesting_shares,
      'total_reward_fund_hive',  o.total_reward_fund_hive,
      'virtual_supply', o.virtual_supply,
      'current_supply', o.current_supply,
      'current_hbd_supply', o.current_hbd_supply,
      'dhf_interval_ledger', o.dhf_interval_ledger,
      'created_at', o.created_at,
      'age', NOW() - o.created_at
    )
  FROM hive.blocks_view o WHERE o.created_at BETWEEN _timestamp - interval '2 seconds' AND _timestamp ORDER BY o.created_at LIMIT 1
  ;


END
$$
;

CREATE OR REPLACE FUNCTION hafbe_backend.get_latest_blocks(_limit INT)
RETURNS SETOF hafbe_types.get_latest_blocks
LANGUAGE 'plpgsql' STABLE
SET JIT=OFF
SET join_collapse_limit=16
SET from_collapse_limit=16
AS
$$
BEGIN
RETURN QUERY
WITH selected AS MATERIALIZED (
SELECT o.num as block_num,
 a.name::TEXT as witness
FROM hive.blocks_view o
JOIN hive.accounts_view a ON a.id = o.producer_account_id
ORDER BY o.num DESC LIMIT _limit
),
selected2 AS MATERIALIZED (
Select s.block_num, s.witness, COUNT(b.op_type_id) as count, b.op_type_id 
FROM hive.operations_view b
JOIN selected s ON s.block_num = b.block_num
GROUP BY b.op_type_id,s.block_num,s.witness
)
SELECT block_num, witness, json_agg(json_build_object(
    'count', count,
    'op_type_id', op_type_id
)) FROM selected2
GROUP BY block_num, witness
ORDER BY block_num DESC;
END
$$                            
;