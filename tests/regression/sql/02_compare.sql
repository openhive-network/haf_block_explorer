-- =============================================================================
-- HAF Block Explorer Regression Test - Comparison Functions
-- =============================================================================
--
-- PURPOSE:
--   Functions to compare HAF Block Explorer's computed values against expected
--   values loaded from hived snapshots.
--
-- FUNCTIONS:
--   hafbe_test.compare_accounts()           - Compare all accounts
--   hafbe_test.compare_witnesses()          - Compare all witnesses
--   hafbe_test.get_account_comparison(int)  - Debug helper for accounts
--   hafbe_test.get_witness_comparison(int)  - Debug helper for witnesses
--
-- =============================================================================

SET ROLE hafbe_owner;

-- -----------------------------------------------------------------------------
-- Account comparison function
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION hafbe_test.compare_accounts()
RETURNS void
LANGUAGE 'plpgsql'
VOLATILE
AS
$$
BEGIN
    RAISE NOTICE 'Comparing hafbe account stats with expected values...';

    WITH expected_accounts AS MATERIALIZED (
        SELECT
            account_id,
            witnesses_voted_for,
            can_vote,
            mined,
            last_account_recovery,
            created,
            proxy,
            last_vote_time,
            recovery_account
        FROM hafbe_test.expected_account_stats
    ),
    witnesses_voted_for AS MATERIALIZED (
        SELECT cwvv.voter_id AS account_id, COUNT(*)::INT AS witnesses_voted_for
        FROM hafbe_app.current_witness_votes cwvv
        GROUP BY cwvv.voter_id
    ),
    account_params AS MATERIALIZED (
        SELECT ap.account AS account_id, ap.can_vote, ap.mined, ap.last_account_recovery, ap.created, ap.recovery_account
        FROM hafbe_app.account_parameters ap
    ),
    proxy_account_id AS MATERIALIZED (
        SELECT cap.account_id, cap.proxy_id
        FROM hafbe_app.current_account_proxies cap
    ),
    computed AS MATERIALIZED (
        SELECT
            ea.account_id,
            ea.witnesses_voted_for AS expected_witnesses_voted_for,
            ea.can_vote AS expected_can_vote,
            ea.mined AS expected_mined,
            ea.last_account_recovery AS expected_last_account_recovery,
            ea.created AS expected_created,
            ea.proxy AS expected_proxy,
            ea.recovery_account AS expected_recovery_account,
            COALESCE(wvf.witnesses_voted_for, 0) AS current_witnesses_voted_for,
            COALESCE(ap.can_vote, TRUE) AS current_can_vote,
            COALESCE(ap.mined, TRUE) AS current_mined,
            COALESCE(ap.last_account_recovery, '1970-01-01T00:00:00') AS current_last_account_recovery,
            COALESCE(ap.created, '1970-01-01T00:00:00') AS current_created,
            COALESCE(pai.proxy_id, NULL) AS current_proxy,
            COALESCE(ap.recovery_account, '') AS current_recovery_account
        FROM expected_accounts ea
        LEFT JOIN witnesses_voted_for wvf ON wvf.account_id = ea.account_id
        LEFT JOIN account_params ap ON ap.account_id = ea.account_id
        LEFT JOIN proxy_account_id pai ON pai.account_id = ea.account_id
    )
    INSERT INTO hafbe_test.differing_accounts
    SELECT account_id FROM computed
    WHERE account_id > 4 AND (
        expected_witnesses_voted_for != current_witnesses_voted_for
        OR expected_can_vote != current_can_vote
        OR expected_mined != current_mined
        OR expected_last_account_recovery != current_last_account_recovery
        OR expected_created != current_created
        OR expected_proxy IS DISTINCT FROM current_proxy
        OR expected_recovery_account != current_recovery_account
    );

    RAISE NOTICE 'Account comparison complete.';
END
$$;

-- -----------------------------------------------------------------------------
-- Witness comparison function
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION hafbe_test.compare_witnesses()
RETURNS void
LANGUAGE 'plpgsql'
VOLATILE
AS
$$
BEGIN
    RAISE NOTICE 'Comparing hafbe witness props with expected values...';

    WITH expected_witnesses AS MATERIALIZED (
        SELECT
            witness_id,
            url,
            vests,
            missed_blocks,
            last_confirmed_block_num,
            signing_key,
            version,
            account_creation_fee,
            block_size,
            hbd_interest_rate,
            price_feed,
            feed_updated_at
        FROM hafbe_test.expected_witness_props
    ),
    hafbe_witnesses AS MATERIALIZED (
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
    compared AS MATERIALIZED (
        SELECT
            ew.witness_id,
            ew.url AS expected_url,
            ew.vests AS expected_vests,
            ew.missed_blocks AS expected_missed_blocks,
            ew.last_confirmed_block_num AS expected_last_confirmed_block_num,
            ew.signing_key AS expected_signing_key,
            ew.version AS expected_version,
            ew.account_creation_fee AS expected_account_creation_fee,
            ew.block_size AS expected_block_size,
            ew.hbd_interest_rate AS expected_hbd_interest_rate,
            ew.price_feed AS expected_price_feed,
            hw.url AS current_url,
            hw.vests AS current_vests,
            hw.missed_blocks AS current_missed_blocks,
            hw.last_confirmed_block_num AS current_last_confirmed_block_num,
            hw.signing_key AS current_signing_key,
            hw.version AS current_version,
            hw.account_creation_fee AS current_account_creation_fee,
            hw.block_size AS current_block_size,
            hw.hbd_interest_rate AS current_hbd_interest_rate,
            hw.price_feed AS current_price_feed
        FROM expected_witnesses ew
        LEFT JOIN hafbe_witnesses hw ON hw.witness_id = ew.witness_id
    )
    INSERT INTO hafbe_test.differing_witnesses
    SELECT witness_id FROM compared
    WHERE witness_id > 4 AND (
        expected_url != current_url
        OR expected_vests != current_vests::BIGINT
        OR expected_missed_blocks != current_missed_blocks
        OR expected_last_confirmed_block_num != current_last_confirmed_block_num
        OR expected_signing_key != current_signing_key
        OR expected_version != current_version
        OR expected_account_creation_fee != current_account_creation_fee
        OR expected_block_size != current_block_size
        OR expected_hbd_interest_rate != current_hbd_interest_rate
        OR expected_price_feed != current_price_feed
    );

    RAISE NOTICE 'Witness comparison complete.';
END
$$;

-- -----------------------------------------------------------------------------
-- Debug helper for accounts
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION hafbe_test.get_account_comparison(_account_id INT)
RETURNS SETOF hafbe_test.account_comparison_type
LANGUAGE 'plpgsql'
STABLE
AS
$$
BEGIN
    -- Return expected values (row 1)
    RETURN QUERY
    SELECT
        account_id,
        witnesses_voted_for,
        can_vote,
        mined,
        last_account_recovery,
        created,
        proxy,
        last_vote_time,
        recovery_account
    FROM hafbe_test.expected_account_stats
    WHERE account_id = _account_id;

    -- Return computed values (row 2)
    RETURN QUERY
    WITH witnesses_voted_for AS (
        SELECT cwvv.voter_id AS account_id, COUNT(*)::INT AS witnesses_voted_for
        FROM hafbe_app.current_witness_votes cwvv
        WHERE cwvv.voter_id = _account_id
        GROUP BY cwvv.voter_id
    ),
    account_params AS (
        SELECT ap.account AS account_id, ap.can_vote, ap.mined, ap.last_account_recovery, ap.created, ap.recovery_account
        FROM hafbe_app.account_parameters ap
        WHERE ap.account = _account_id
    ),
    proxy_account_id AS (
        SELECT cap.account_id, cap.proxy_id
        FROM hafbe_app.current_account_proxies cap
        WHERE cap.account_id = _account_id
    )
    SELECT
        _account_id,
        COALESCE(wvf.witnesses_voted_for, 0),
        COALESCE(ap.can_vote, TRUE),
        COALESCE(ap.mined, TRUE),
        COALESCE(ap.last_account_recovery, '1970-01-01T00:00:00'::TIMESTAMP),
        COALESCE(ap.created, '1970-01-01T00:00:00'::TIMESTAMP),
        pai.proxy_id,
        NULL::TIMESTAMP,  -- last_vote_time not tracked in hafbe_app
        COALESCE(ap.recovery_account, '')
    FROM (SELECT 1) AS dummy
    LEFT JOIN witnesses_voted_for wvf ON TRUE
    LEFT JOIN account_params ap ON TRUE
    LEFT JOIN proxy_account_id pai ON TRUE;
END
$$;

-- -----------------------------------------------------------------------------
-- Debug helper for witnesses
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION hafbe_test.get_witness_comparison(_witness_id INT)
RETURNS SETOF hafbe_test.witness_comparison_type
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
    _witness_name TEXT := (SELECT av.name FROM hive.accounts_view av WHERE av.id = _witness_id);
BEGIN
    -- Return expected values (row 1)
    RETURN QUERY
    SELECT
        witness_id,
        url,
        vests,
        missed_blocks,
        last_confirmed_block_num,
        signing_key,
        version,
        account_creation_fee,
        block_size,
        hbd_interest_rate,
        price_feed,
        feed_updated_at
    FROM hafbe_test.expected_witness_props
    WHERE witness_id = _witness_id;

    -- Return computed values (row 2)
    RETURN QUERY
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
