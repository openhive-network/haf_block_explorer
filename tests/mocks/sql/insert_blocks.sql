-- =============================================================================
-- Insert mock block headers into hafd.blocks.
-- =============================================================================

SET ROLE hafbe_owner;

CREATE OR REPLACE FUNCTION hafbe_backend.insert_mock_blocks(IN _block_json JSON)
RETURNS VOID
LANGUAGE plpgsql
VOLATILE
AS $$
BEGIN
  INSERT INTO hafd.blocks(
    num, hash, prev, created_at, producer_account_id,
    transaction_merkle_root, extensions, witness_signature, signing_key,
    hbd_interest_rate, total_vesting_fund_hive, total_vesting_shares,
    total_reward_fund_hive, virtual_supply, current_supply,
    current_hbd_supply, dhf_interval_ledger
  )
  SELECT
    block_num,
    decode(hash, 'hex'),
    decode(prev, 'hex'),
    created_at,
    (SELECT av.id FROM hive.accounts_view av WHERE av.name = producer_account),
    decode(transaction_merkle_root, 'hex'),
    NULL,
    decode(witness_signature, 'hex'),
    signing_key,
    hbd_interest_rate::INT,
    total_vesting_fund_hive::numeric,
    total_vesting_shares::numeric,
    total_reward_fund_hive::numeric,
    virtual_supply::numeric,
    current_supply::numeric,
    current_hbd_supply::numeric,
    dhf_interval_ledger::numeric
  FROM json_populate_recordset(
    NULL::hafbe_backend.mock_block_type,
    _block_json->'blocks'
  )
  -- Idempotent: re-running the installer should be a no-op for already-loaded blocks.
  ON CONFLICT (num) DO NOTHING;
END
$$;

RESET ROLE;
