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
    (SELECT av.id FROM hive.accounts_view av WHERE av.name = (account_data->>'proxy')) AS proxy,
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



RESET ROLE;
