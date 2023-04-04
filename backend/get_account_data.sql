CREATE OR REPLACE FUNCTION hafbe_backend.get_account_id(_account TEXT)
RETURNS INT
LANGUAGE 'plpgsql'
AS
$$
BEGIN
  RETURN id FROM hive.accounts_view WHERE name = _account;
END
$$
;

CREATE OR REPLACE FUNCTION hafbe_backend.get_account(_account TEXT)
RETURNS JSON
LANGUAGE 'plpython3u'
AS
$$
  import subprocess
  import json

  return json.dumps(
    json.loads(
      subprocess.check_output([
        """
        curl -X POST https://api.hive.blog \
          -H 'Content-Type: application/json' \
          -d '{"jsonrpc": "2.0", "method": "condenser_api.get_accounts", "params": [["%s"]], "id": null}'
        """ % _account
      ], shell=True).decode('utf-8')
    )['result'][0]
  )
$$
;

CREATE OR REPLACE FUNCTION hafbe_backend.parse_profile_picture(_account_data JSON, _key TEXT)
RETURNS TEXT
LANGUAGE 'plpgsql'
AS
$$
DECLARE
  __profile_image_url TEXT;
  __response_code INT;
BEGIN
  BEGIN
    SELECT INTO __profile_image_url ( (
      ((_account_data->>_key)::JSON)->>'profile'
      )::JSON )->>'profile_image';
  EXCEPTION WHEN invalid_text_representation THEN
    SELECT NULL INTO __profile_image_url;
  END;

  IF __profile_image_url IS NOT NULL AND LENGTH(__profile_image_url) != 0 THEN
    SELECT hafbe_backend.validate_profile_picture_link(__profile_image_url) INTO __response_code;
  END IF;

  IF __profile_image_url IS NOT NULL AND LENGTH(__profile_image_url) != 0 AND __response_code > 299 THEN
    SELECT NULL INTO __profile_image_url;
  END IF;

  RETURN __profile_image_url;
END
$$
;

CREATE OR REPLACE FUNCTION hafbe_backend.validate_profile_picture_link(__profile_image_url TEXT)
RETURNS INT
LANGUAGE 'plpython3u'
AS 
$$
  import subprocess

  try:
    res = int(
      subprocess.check_output([
        f'curl -s -o /dev/null -I -w "%{{http_code}}" "{__profile_image_url}"'
      ], shell=True).decode('utf-8')
    )
  except:
    res = 500
  return res
$$
;

CREATE OR REPLACE FUNCTION hafbe_backend.get_account_resource_credits(_account TEXT)
RETURNS JSON
LANGUAGE 'plpython3u'
AS 
$$
  import subprocess
  import json

  return json.dumps(
    json.loads(
      subprocess.check_output([
        """
        curl -X POST https://api.hive.blog \
          -H 'Content-Type: application/json' \
          -d '{"jsonrpc": "2.0", "method": "rc_api.find_rc_accounts", "params": {"accounts":["%s"]}, "id": null}'
        """ % _account
      ], shell=True).decode('utf-8')
    )['result']['rc_accounts'][0]
  )
$$
;
