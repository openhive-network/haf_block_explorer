SET ROLE hafbe_owner;

/** openapi:components:schemas
hafbe_types.array_of_proxy_power:
  type: array
  items:
    $ref: '#/components/schemas/hafbe_types.proxy_power'
*/

/** openapi:paths
'/accounts/{account-name}/proxy-power':
  get:
    tags:
      - Accounts
    summary: Get delegators and total vested power they contribute via witness-proxy
    description: |
      Lists every account that has set **{account-name}** as its witness proxy,
      the date the proxy was set, and the total vested power contributed
      (own vesting_shares plus sum of proxied vesting shares levels 1–4 and decreased by delayed vests).

      SQL example:
      * `SELECT * FROM hafbe_endpoints.get_account_proxies_power(''gtg'', 1);`

      REST call example:
      * `GET ''https://%1$s/hafbe-api/accounts/gtg/proxy-power?page=1''`
    operationId: hafbe_endpoints.get_account_proxies_power
    parameters:
      - in: path
        name: account-name
        required: true
        schema:
          type: string
        description: Name of the proxy account
      - in: query
        name: page
        required: false
        schema:
          type: integer
          minimum: 1
          default: 1
        description: 1-based page number (100 rows per page)
    responses:
      '200':
        description: Array of delegators and their total vested power
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/hafbe_types.array_of_proxy_power'
            exaxmple: [
              {
                "account": "geoffrey",
                "proxied_vests": 30847126195440,
                "proxy_date": "2016-08-09T06:52:03"
              }
            ]
      '404':
        description: No such account in the database
*/
-- openapi-generated-code-begin
DROP FUNCTION IF EXISTS hafbe_endpoints.get_account_proxies_power;
CREATE OR REPLACE FUNCTION hafbe_endpoints.get_account_proxies_power(
    "account-name" TEXT,
    "page" INT = 1
)
RETURNS SETOF hafbe_types.proxy_power 
-- openapi-generated-code-end
/*------------------------------------------
  hafbe_endpoints.get_account_proxies_power
------------------------------------------*/
LANGUAGE plpgsql
STABLE
SET JIT = OFF
SET join_collapse_limit = 16
SET from_collapse_limit = 16
AS
$$
DECLARE
  _account_id INT := hafbe_backend.get_account_id("account-name");
BEGIN
  -- validate that page ≥ 1
  PERFORM hafbe_exceptions.validate_negative_page(page);

  -- set short public cache
  PERFORM set_config(
    'response.headers',
    '[{"Cache-Control":"public, max-age=5"}]',
    true
  );

  -- ensure account exists
  IF _account_id IS NULL THEN
    PERFORM hafbe_exceptions.rest_raise_missing_account("account-name");
  END IF;

  -- delegate to ID-based backend logic
  RETURN QUERY
    SELECT *
      FROM hafbe_backend.get_account_proxies_power(
             _account_id,
             page
           );
END;
$$;

RESET ROLE;
