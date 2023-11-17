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
    account_data->>'name'AS name,
    (account_data->>'witnesses_voted_for')::INT AS witnesses_voted_for,
    (account_data->>'can_vote')::BOOLEAN AS can_vote,
    (account_data->>'mined')::BOOLEAN AS mined,
    (account_data->>'recovery_account') AS recovery_account,
    (account_data->>'last_account_recovery')::TIMESTAMP AS last_account_recovery,
    (account_data->>'created')::TIMESTAMP AS created,
    (account_data->>'proxy') AS proxy,
    (account_data->>'last_post')::TIMESTAMP AS last_post,
    (account_data->>'last_root_post')::TIMESTAMP AS last_root_post,
    (account_data->>'last_vote_time')::TIMESTAMP AS last_vote_time,
    (account_data->>'post_count')::BIGINT AS post_count; 
END
$$;

DROP TYPE IF EXISTS hafbe_backend.account_type CASCADE; -- noqa: LT01
CREATE TYPE hafbe_backend.account_type AS
(
    name TEXT,
    witnesses_voted_for INT,
    can_vote BOOLEAN,
    mined BOOLEAN,
    last_account_recovery TIMESTAMP,
    created TIMESTAMP,
    proxy TEXT,
    last_post TIMESTAMP,
    last_root_post TIMESTAMP,
    last_vote_time TIMESTAMP,
    post_count INT
);

CREATE OR REPLACE FUNCTION hafbe_backend.get_account_setof(_account text)
RETURNS hafbe_backend.account_type -- noqa: LT01
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
  __account_id INT := (SELECT id FROM hive.accounts_view WHERE name = _account);
  __result hafbe_backend.account_type;
BEGIN
  SELECT
    _account,
    COALESCE(_result_votes.witnesses_voted_for, 0) AS witnesses_voted_for,

    COALESCE(_result_parameters.can_vote, TRUE) AS can_vote,
    COALESCE(_result_parameters.mined, TRUE) AS mined,
    COALESCE(_result_parameters.last_account_recovery, '1970-01-01T00:00:00') AS last_account_recovery,
    COALESCE(_result_parameters.created,'1970-01-01T00:00:00') AS created,

    COALESCE(_result_proxy.get_account_proxy, '') AS proxy,

    COALESCE(_result_post.last_post, '1970-01-01T00:00:00') AS last_post,
    COALESCE(_result_post.last_root_post, '1970-01-01T00:00:00') AS last_root_post,
    COALESCE(_result_post.last_vote_time, '1970-01-01T00:00:00') AS last_vote_time,
    COALESCE(_result_post.post_count, 0) AS post_count
  INTO __result
  FROM
    (SELECT * FROM hafbe_backend.get_last_post_vote_time(__account_id)) AS _result_post,
    (SELECT * FROM hafbe_backend.get_account_proxy(__account_id)) AS _result_proxy,
    (SELECT * FROM hafbe_backend.get_account_parameters(__account_id)) AS _result_parameters,
    (SELECT * FROM hafbe_backend.get_account_votes(__account_id)) AS _result_votes
;

  RETURN __result;
END
$$;

RESET ROLE;
