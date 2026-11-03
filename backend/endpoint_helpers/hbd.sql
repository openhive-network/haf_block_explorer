SET ROLE hafbe_owner;

/*
 * The HBD debt ratio the chain acts on (hived database::calculate_HBD_percent), as a percent.
 *
 * Inputs are the stored block values in the chain's smallest units (milli-HBD, milli-HIVE)
 * and the treasury's liquid HBD at the same block. virtual_supply - hive_supply is the HBD
 * supply valued in HIVE at the effective median price (hard-cap adjustment included), so
 * that price is (virtual_supply - hive_supply) / hbd_supply.
 *
 * Before HF24 (_treasury_excluded false) the protocol ratio is the gross share,
 * 100 * (virtual_supply - hive_supply) / virtual_supply. From HF24 the treasury's liquid
 * HBD is left out of the HBD supply (clamped at 0) and the virtual supply is recomputed
 * from what remains; an empty remainder gives 0, as in hived. Savings and reward HBD of
 * the treasury are not subtracted: the protocol uses its liquid balance only.
 *
 * Rounded to three decimals. The chain computes basis points (uint16, rounded since HF21),
 * so the two agree up to its 0.01% step. NULL when virtual_supply is 0.
 */
CREATE OR REPLACE FUNCTION hafbe_backend.hbd_protocol_debt_ratio_pct(
    _hbd_supply        BIGINT,
    _hive_supply       BIGINT,
    _virtual_supply    BIGINT,
    _treasury_hbd      BIGINT,
    _treasury_excluded BOOLEAN
)
RETURNS NUMERIC
LANGUAGE plpgsql
IMMUTABLE
AS
$$
DECLARE
  __hbd_in_hive NUMERIC := _virtual_supply - _hive_supply;
  __remaining   BIGINT;
  __value       NUMERIC;
BEGIN
  IF NOT _treasury_excluded THEN
    RETURN ROUND(100::NUMERIC * __hbd_in_hive / NULLIF(_virtual_supply, 0), 3);
  END IF;

  __remaining := GREATEST(_hbd_supply - COALESCE(_treasury_hbd, 0), 0);
  IF __remaining = 0 THEN
    RETURN CASE WHEN _virtual_supply = 0 THEN NULL ELSE 0 END;
  END IF;

  __value := __hbd_in_hive * __remaining / _hbd_supply;
  RETURN ROUND(100::NUMERIC * __value / NULLIF(__value + _hive_supply, 0), 3);
END
$$;

RESET ROLE;
