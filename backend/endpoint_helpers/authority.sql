SET ROLE hafbe_owner;

CREATE OR REPLACE FUNCTION hafbe_backend.get_account_authority(
    _account_id INT,
    _key_kind hafd.key_type -- noqa: LT01, CP05
)
RETURNS hafbe_types.authority_type -- noqa: LT01, CP05
LANGUAGE 'plpgsql'
STABLE
SET JIT = OFF
SET join_collapse_limit = 16
SET from_collapse_limit = 16
AS
$$
DECLARE
  _result hafbe_types.authority_type;
BEGIN
RETURN (
  WITH get_key_auth AS 
  (
    SELECT ARRAY[hive.public_key_to_string(keys.key), active_key_auths.w::TEXT] as key_auth
    FROM hafd.hafbe_app_keyauth_a active_key_auths
    JOIN hafd.hafbe_app_keyauth_k keys ON active_key_auths.key_serial_id = keys.key_id
    WHERE active_key_auths.account_id = _account_id 
    AND active_key_auths.key_kind = _key_kind
    AND (active_key_auths.key_kind != 'MEMO' OR active_key_auths.key_kind != 'WITNESS_SIGNING')
    ORDER BY hive.public_key_to_string(keys.key)
  ),
  get_account_auth AS 
  (
    SELECT ARRAY[av.name, active_account_auths.w::TEXT] AS key_auth
    FROM hafd.hafbe_app_accountauth_a active_account_auths
    JOIN hive.accounts_view av ON active_account_auths.account_auth_id = av.id
    WHERE active_account_auths.account_id = _account_id
    AND active_account_auths.key_kind = _key_kind
    ORDER BY av.name
  ),
  get_weight_threshold AS 
  (
    SELECT wt.weight_threshold
    FROM hafd.hafbe_app_authority_definition wt
    WHERE wt.account_id = _account_id
    AND wt.key_kind = _key_kind
  )
  SELECT ROW(
      COALESCE(
        (
          SELECT array_agg(gka.key_auth) AS key_auth
          FROM get_key_auth gka
        ), '{}')::TEXT[],
      COALESCE(
        (
          SELECT array_agg(gaa.key_auth) 
          FROM get_account_auth gaa 
        ), '{}')::TEXT[],
      COALESCE(
        (
          SELECT wt.weight_threshold FROM get_weight_threshold wt
        ), 1))
);

END
$$;

CREATE OR REPLACE FUNCTION hafbe_backend.get_account_memo(
    _account_id INT
)
RETURNS TEXT -- noqa: LT01, CP05
LANGUAGE 'plpgsql'
STABLE
SET JIT = OFF
SET join_collapse_limit = 16
SET from_collapse_limit = 16
AS
$$
BEGIN
RETURN (
  COALESCE(
    (
      SELECT hive.public_key_to_string(keys.key) as key_auth
      FROM hafd.hafbe_app_keyauth_a active_key_auths
      JOIN hafd.hafbe_app_keyauth_k keys ON active_key_auths.key_serial_id = keys.key_id
      WHERE active_key_auths.account_id = _account_id 
      AND active_key_auths.key_kind = 'MEMO'
    ), ''
  )
);

END
$$;

CREATE OR REPLACE FUNCTION hafbe_backend.get_account_witness_signing(
    _account_id INT
)
RETURNS TEXT -- noqa: LT01, CP05
LANGUAGE 'plpgsql'
STABLE
SET JIT = OFF
SET join_collapse_limit = 16
SET from_collapse_limit = 16
AS
$$
BEGIN
RETURN (
  COALESCE(
    (
      SELECT hive.public_key_to_string(keys.key) as key_auth
      FROM hafd.hafbe_app_keyauth_a active_key_auths
      JOIN hafd.hafbe_app_keyauth_k keys ON active_key_auths.key_serial_id = keys.key_id
      WHERE active_key_auths.account_id = _account_id
      AND active_key_auths.key_kind = 'WITNESS_SIGNING'
    ), ''
  )
);

END
$$;

RESET ROLE;
