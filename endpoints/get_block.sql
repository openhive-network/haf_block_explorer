SET ROLE hafbe_owner;

CREATE OR REPLACE FUNCTION hafbe_endpoints.get_head_block_num()
RETURNS INT
LANGUAGE 'plpgsql' STABLE
AS
$$
BEGIN
RETURN num FROM hive.blocks_view ORDER BY num DESC LIMIT 1
;

END
$$
;

CREATE OR REPLACE FUNCTION hafbe_endpoints.get_block(_block_num INT)
RETURNS hafbe_types.block
LANGUAGE 'plpgsql' STABLE
SET JIT=OFF
SET join_collapse_limit=16
SET from_collapse_limit=16
AS
$$
BEGIN
RETURN (
SELECT ROW(
  b.num,   
  b.hash,
  b.prev,
  a.name::TEXT,
  b.transaction_merkle_root,
  b.extensions,
  b.witness_signature,
  b.signing_key,
  b.hbd_interest_rate::numeric,
  b.total_vesting_fund_hive::numeric,
  b.total_vesting_shares::numeric,
  b.total_reward_fund_hive::numeric,
  b.virtual_supply::numeric,
  b.current_supply::numeric,
  b.current_hbd_supply::numeric,
  b.dhf_interval_ledger::numeric,
  b.created_at,
  NOW() - b.created_at)
FROM hive.blocks_view b
JOIN hive.accounts_view a ON a.id = b.producer_account_id
WHERE num = _block_num
);

END
$$
;

CREATE OR REPLACE FUNCTION hafbe_endpoints.get_block_by_time(_timestamp TIMESTAMP)
RETURNS INT
LANGUAGE 'plpgsql' STABLE
AS
$$
BEGIN
RETURN o.num
FROM hive.blocks_view o WHERE o.created_at BETWEEN _timestamp - interval '2 seconds' AND _timestamp ORDER BY o.created_at LIMIT 1
;

END
$$
;

CREATE OR REPLACE FUNCTION hafbe_endpoints.get_latest_blocks(_limit INT = 10)
RETURNS SETOF hafbe_types.get_latest_blocks
LANGUAGE 'plpgsql' STABLE
SET JIT=OFF
SET join_collapse_limit=16
SET from_collapse_limit=16
AS
$$
BEGIN
RETURN QUERY
  WITH select_block_range AS MATERIALIZED (
    SELECT 
      o.num as block_num,
      a.name::TEXT as witness
    FROM hive.blocks_view o
    JOIN hive.accounts_view a ON a.id = o.producer_account_id
    ORDER BY o.num DESC LIMIT _limit
  ),
  join_operations AS MATERIALIZED (
    SELECT 
      s.block_num, 
      s.witness, 
      COUNT(b.op_type_id) as count, 
      b.op_type_id 
    FROM hive.operations_view b
    JOIN select_block_range s ON s.block_num = b.block_num
    GROUP BY b.op_type_id,s.block_num,s.witness
  )
    SELECT block_num, witness, json_agg(json_build_object(
      'count', count,
      'op_type_id', op_type_id
    )) FROM join_operations
    GROUP BY block_num, witness
    ORDER BY block_num DESC
;

END
$$                            
;

RESET ROLE;
