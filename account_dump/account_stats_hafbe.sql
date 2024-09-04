SET ROLE hafbe_owner;

CREATE OR REPLACE FUNCTION hafbe_backend.dump_current_account_stats(account_data jsonb)
RETURNS void
LANGUAGE 'plpgsql'
VOLATILE
AS
$$
BEGIN
INSERT INTO hafbe_backend.account_balances 

SELECT
    (account_data->>'id')::INT AS account_id,
    (account_data->>'witnesses_voted_for')::INT AS witnesses_voted_for,
    (account_data->>'can_vote')::BOOLEAN AS can_vote,
    (account_data->>'mined')::BOOLEAN AS mined,
    (account_data->>'last_account_recovery')::TIMESTAMP AS last_account_recovery,
    (account_data->>'created')::TIMESTAMP AS created,
    (SELECT av.id FROM hafbe_app.accounts_view av WHERE av.name = (account_data->>'proxy')) AS proxy,
--    (account_data->>'last_post')::TIMESTAMP AS last_post,
--    (account_data->>'last_root_post')::TIMESTAMP AS last_root_post,
    (account_data->>'last_vote_time')::TIMESTAMP AS last_vote_time,
--    (account_data->>'post_count')::BIGINT AS post_count; 
    (account_data->>'recovery_account')::TEXT AS recovery_account;

END
$$;

DROP TYPE IF EXISTS hafbe_backend.account_type CASCADE; -- noqa: LT01
CREATE TYPE hafbe_backend.account_type AS
(
    account_id INT,
    witnesses_voted_for INT,
    can_vote BOOLEAN,
    mined BOOLEAN,
    last_account_recovery TIMESTAMP,
    created TIMESTAMP,
    proxy INT,
    last_vote_time TIMESTAMP,
    recovery_account TEXT

);

CREATE OR REPLACE FUNCTION hafbe_backend.dump_current_witness_props(witness_data jsonb)
RETURNS void
LANGUAGE 'plpgsql'
VOLATILE
AS
$$
BEGIN
INSERT INTO hafbe_backend.witness_props 

SELECT
    (SELECT av.id FROM hive.accounts_view av WHERE av.name = (witness_data->>'owner')::TEXT)::INT AS witness_id,
    (witness_data->>'url')::TEXT AS url,
    (witness_data->>'votes')::BIGINT AS vests,
    (witness_data->>'total_missed')::INT AS missed_blocks,
    (witness_data->>'last_confirmed_block_num')::INT AS last_confirmed_block_num,
    (witness_data->>'signing_key')::TEXT AS signing_key,
    (witness_data->>'running_version')::TEXT AS version,
    (REGEXP_REPLACE((witness_data->'props'->>'account_creation_fee'), '[^0-9]', '', 'g'))::INT AS account_creation_fee,
    (witness_data->'props'->>'maximum_block_size')::INT AS block_size,
    (witness_data->'props'->>'hbd_interest_rate')::INT AS hbd_interest_rate,
    (REGEXP_REPLACE((witness_data->'hbd_exchange_rate'->>'base'), '[^0-9.]', '', 'g'))::numeric AS price_feed,
    (witness_data->>'last_hbd_exchange_update')::TIMESTAMP AS feed_updated_at;

END
$$;

DROP TYPE IF EXISTS hafbe_backend.witness_type CASCADE; -- noqa: LT01
CREATE TYPE hafbe_backend.witness_type AS
(
    witness_id INT,
    url TEXT,
    vests BIGINT,
    missed_blocks INT,
    last_confirmed_block_num INT,
    signing_key TEXT,
    version TEXT,
    account_creation_fee INT,
    block_size INT,
    hbd_interest_rate INT,
    price_feed NUMERIC,
    feed_updated_at TIMESTAMP
);

RESET ROLE;
