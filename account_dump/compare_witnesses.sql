SET ROLE hafbe_owner;

CREATE OR REPLACE FUNCTION hafbe_backend.compare_witnesses()
RETURNS void
LANGUAGE 'plpgsql'
VOLATILE
AS
$$
BEGIN
RAISE NOTICE 'Comparing hafbe parameters with account_dump...';
WITH hived_witness_properties AS MATERIALIZED
(
  SELECT 
    wp.witness_id,
    wp.url,
    wp.vests,
    wp.missed_blocks,
    wp.last_confirmed_block_num,
    wp.signing_key,
    wp.version,
    wp.account_creation_fee,
    wp.block_size,
    wp.hbd_interest_rate,
    wp.price_feed,
    wp.feed_updated_at
  FROM hafbe_backend.witness_props wp
),
hafbe_witness_properties AS MATERIALIZED
(
  SELECT 
    av.id AS witness_id,
    gw.url,
    gw.vests,
    gw.missed_blocks,
    gw.last_confirmed_block_num,
    gw.signing_key,
    gw.version,
    gw.account_creation_fee,
    gw.block_size,
    gw.hbd_interest_rate,
    gw.price_feed,
    gw.feed_updated_at
  FROM hafbe_backend.get_witnesses(1000, 0, 'votes', 'desc') gw
  JOIN hive.accounts_view av ON av.name = gw.witness_name
),
compare_witnesses AS MATERIALIZED 
(
  SELECT
    hwp.witness_id,

    -- props from hived
    hwp.url,
    hwp.vests,
    hwp.missed_blocks,
    hwp.last_confirmed_block_num,
    hwp.signing_key,
    hwp.version,
    hwp.account_creation_fee,
    hwp.block_size,
    hwp.hbd_interest_rate,
    hwp.price_feed,
    hwp.feed_updated_at,

    -- props from hafbe
    hbewp.url AS hafbe_url,
    hbewp.vests AS hafbe_vests,
    hbewp.missed_blocks AS hafbe_missed_blocks,
    hbewp.last_confirmed_block_num AS hafbe_last_confirmed_block_num,
    hbewp.signing_key AS hafbe_signing_key,
    hbewp.version AS hafbe_version,
    hbewp.account_creation_fee AS hafbe_account_creation_fee,
    hbewp.block_size AS hafbe_block_size,
    hbewp.hbd_interest_rate AS hafbe_hbd_interest_rate,
    hbewp.price_feed AS hafbe_price_feed,
    hbewp.feed_updated_at AS hafbe_feed_updated_at

  FROM hived_witness_properties hwp
  LEFT JOIN hafbe_witness_properties hbewp ON hbewp.witness_id = hwp.witness_id
)
INSERT INTO hafbe_backend.differing_witnesses
SELECT cw.witness_id 
FROM compare_witnesses cw
WHERE cw.witness_id > 4 AND (
  cw.url != cw.hafbe_url
  OR cw.vests != cw.hafbe_vests::BIGINT
  OR cw.missed_blocks != cw.hafbe_missed_blocks
  OR cw.last_confirmed_block_num != cw.hafbe_last_confirmed_block_num
  OR cw.signing_key != cw.hafbe_signing_key
  OR cw.version != cw.hafbe_version
  OR cw.account_creation_fee != cw.hafbe_account_creation_fee
  OR cw.block_size != cw.hafbe_block_size
  OR cw.hbd_interest_rate != cw.hafbe_hbd_interest_rate
  OR cw.price_feed != cw.hafbe_price_feed
--  OR cw.feed_updated_at != cw.hafbe_feed_updated_at
  );

END
$$;

CREATE OR REPLACE FUNCTION hafbe_backend.compare_differing_witness(_witness_id INT)
RETURNS SETOF hafbe_backend.witness_type -- noqa: LT01
LANGUAGE 'plpgsql' STABLE
AS
$$
DECLARE
  _witness_name TEXT := (SELECT av.name FROM hive.accounts_view av WHERE av.id = _witness_id);
BEGIN
  RETURN QUERY 
    SELECT
      _witness_id,
      wp.url,
      wp.vests,
      wp.missed_blocks,
      wp.last_confirmed_block_num,
      wp.signing_key,
      wp.version,
      wp.account_creation_fee,
      wp.block_size,
      wp.hbd_interest_rate,
      wp.price_feed::NUMERIC,
      wp.feed_updated_at
    FROM hafbe_backend.witness_props wp
    WHERE witness_id = _witness_id
    UNION ALL
    SELECT 
      _witness_id,
      gw.url,
      gw.vests::BIGINT,
      gw.missed_blocks,
      gw.last_confirmed_block_num,
      gw.signing_key,
      gw.version,
      gw.account_creation_fee,
      gw.block_size,
      gw.hbd_interest_rate,
      gw.price_feed::NUMERIC,
      gw.feed_updated_at
    FROM hafbe_backend.get_witness(_witness_name) gw;

END
$$;


RESET ROLE;
