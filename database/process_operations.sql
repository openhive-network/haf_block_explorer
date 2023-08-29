CREATE OR REPLACE FUNCTION hafbe_app.process_create_account_operation(_body jsonb, _timestamp TIMESTAMP, _op_type INT)
RETURNS VOID
LANGUAGE 'plpgsql' VOLATILE
AS
$$
BEGIN
WITH create_account_operation AS (
  SELECT
    (SELECT id FROM hive.hafbe_app_accounts_view WHERE name = _body->'value'->>'new_account_name') AS _account,
    _timestamp AS _time,
    _op_type AS _op_type_id
),
insert_created_accounts AS (

  INSERT INTO hafbe_app.account_parameters
  (
    account,
    created,
    mined
  ) 
    SELECT
      _account,
      _time,
      FALSE
    FROM create_account_operation
    WHERE _op_type_id != 80

  ON CONFLICT ON CONSTRAINT pk_account_parameters
  DO UPDATE SET
    created = EXCLUDED.created,
    mined = EXCLUDED.mined
)
  INSERT INTO hafbe_app.account_parameters
  (
    account,
    created
  ) 
  SELECT
    _account,
    _time
  FROM create_account_operation
  WHERE _op_type_id = 80

  ON CONFLICT ON CONSTRAINT pk_account_parameters
  DO UPDATE SET
    created = EXCLUDED.created;
    
END
$$
;

CREATE OR REPLACE FUNCTION hafbe_app.process_pow_operation(_body jsonb, _op_type INT)
RETURNS VOID
LANGUAGE 'plpgsql' VOLATILE
AS
$$
BEGIN
WITH pow_operation AS (
  SELECT
    CASE WHEN _op_type = 14 THEN
    (SELECT id FROM hive.hafbe_app_accounts_view WHERE name = _body->'value'->>'worker_account')
    ELSE
    (SELECT id FROM hive.hafbe_app_accounts_view WHERE name = _body->'value'->'work'->'value'->'input'->>'worker_account')
    END AS _account
)
  INSERT INTO hafbe_app.account_parameters
  (
    account,
    mined
  ) 
  SELECT
    _account,
    TRUE
  FROM pow_operation

  ON CONFLICT ON CONSTRAINT pk_account_parameters
  DO UPDATE SET
    mined = EXCLUDED.mined;

END
$$
;

CREATE OR REPLACE FUNCTION hafbe_app.process_changed_recovery_account_operation(_body jsonb)
RETURNS VOID
LANGUAGE 'plpgsql' VOLATILE
AS
$$
BEGIN
WITH changed_recovery_account_operation AS (
  SELECT
    (SELECT id FROM hive.hafbe_app_accounts_view WHERE name = _body->'value'->>'account') AS _account,
    _body->'value'->>'new_recovery_account' AS _new_recovery_account
)
  INSERT INTO hafbe_app.account_parameters
  (
    account,
    recovery_account
  ) 
  SELECT
    _account,
    _new_recovery_account
  FROM changed_recovery_account_operation

  ON CONFLICT ON CONSTRAINT pk_account_parameters
  DO UPDATE SET
    recovery_account = EXCLUDED.recovery_account;

END
$$
;

CREATE OR REPLACE FUNCTION hafbe_app.process_recover_account_operation(_body jsonb, _timestamp TIMESTAMP)
RETURNS VOID
LANGUAGE 'plpgsql' VOLATILE
AS
$$
BEGIN
WITH recover_account_operation AS (
  SELECT
    (SELECT id FROM hive.hafbe_app_accounts_view WHERE name = _body->'value'->>'account_to_recover') AS _account,
    _timestamp AS _time
)
  INSERT INTO hafbe_app.account_parameters
  (
    account,
    last_account_recovery
  ) 
  SELECT
    _account,
    _time
  FROM recover_account_operation

  ON CONFLICT ON CONSTRAINT pk_account_parameters
  DO UPDATE SET
    last_account_recovery = EXCLUDED.last_account_recovery;

END
$$
;

CREATE OR REPLACE FUNCTION hafbe_app.process_decline_voting_rights_operation(_body jsonb)
RETURNS VOID
LANGUAGE 'plpgsql' VOLATILE
AS
$$
BEGIN
WITH decline_voting_rights_operation AS (
  SELECT
    (SELECT id FROM hive.hafbe_app_accounts_view WHERE name = _body->'value'->>'account') AS _account,
    (CASE WHEN (_body->'value'->>'decline')::BOOLEAN = TRUE THEN FALSE ELSE TRUE END) AS _can_vote
)
  INSERT INTO hafbe_app.account_parameters
  (
    account,
    can_vote
  ) 
  SELECT
    _account,
    _can_vote
  FROM decline_voting_rights_operation

  ON CONFLICT ON CONSTRAINT pk_account_parameters
  DO UPDATE SET
    can_vote = EXCLUDED.can_vote;

END
$$
;

CREATE OR REPLACE FUNCTION hafbe_app.process_comment_operation(_body jsonb, _timestamp TIMESTAMP)
RETURNS VOID
LANGUAGE 'plpgsql' VOLATILE
AS
$$
DECLARE
  parent_author TEXT := (_body->'value'->>'parent_author');
BEGIN
IF parent_author = '' OR parent_author IS NULL THEN

  INSERT INTO hafbe_app.account_posts
  (
    account,
    last_post,
    last_root_post,
    post_count
  ) 
  SELECT
    (SELECT id FROM hive.hafbe_app_accounts_view WHERE name = _body->'value'->>'author'),
    _timestamp,
    _timestamp,
    1

  ON CONFLICT ON CONSTRAINT pk_account_posts
  DO UPDATE SET
    last_post = EXCLUDED.last_post,
    last_root_post = EXCLUDED.last_root_post,
    post_count = hafbe_app.account_posts.post_count + EXCLUDED.post_count;

ELSE

  INSERT INTO hafbe_app.account_posts
  (
    account,
    last_post,
    post_count
  ) 
  SELECT
    (SELECT id FROM hive.hafbe_app_accounts_view WHERE name = _body->'value'->>'author'),
    _timestamp,
    1

  ON CONFLICT ON CONSTRAINT pk_account_posts
  DO UPDATE SET
    last_post = EXCLUDED.last_post,
    post_count = hafbe_app.account_posts.post_count + EXCLUDED.post_count;

END IF;

END
$$
;


CREATE OR REPLACE FUNCTION hafbe_app.process_vote_operation(_body jsonb, _timestamp TIMESTAMP)
RETURNS VOID
LANGUAGE 'plpgsql' VOLATILE
AS
$$
BEGIN

  INSERT INTO hafbe_app.account_posts
  (
  account,
  last_vote_time
  ) 
  SELECT
    (SELECT id FROM hive.hafbe_app_accounts_view WHERE name = _body->'value'->>'voter'),
    _timestamp

  ON CONFLICT ON CONSTRAINT pk_account_posts
  DO UPDATE SET
      last_vote_time = EXCLUDED.last_vote_time;

END
$$
;

