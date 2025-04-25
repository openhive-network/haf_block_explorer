-- Functions used in hafbe_endpoints.get_account

SET ROLE hafbe_owner;

-- ACCOUNT ID
CREATE OR REPLACE FUNCTION hafbe_backend.get_account_id(_account TEXT)
RETURNS INT STABLE
LANGUAGE 'plpgsql'
AS
$$
BEGIN
RETURN 
  av.id 
FROM hive.accounts_view av WHERE av.name = _account
;

END
$$;

CREATE OR REPLACE FUNCTION hafbe_backend.get_account_name(_account_id INT)
RETURNS TEXT STABLE
LANGUAGE 'plpgsql'
AS
$$
BEGIN
RETURN av.name 
FROM hive.accounts_view av
WHERE av.id = _account_id;
END
$$;

RESET ROLE;
