SET ROLE hafbe_owner;

/** openapi:components:schemas
hafbe_backend.array_of_proxy_power:
  type: array
  items:
    $ref: '#/components/schemas/hafbe_backend.proxy_power'
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
        description: 1-based page number (1000 rows per page)
      - in: query
        name: sort
        required: false
        schema:
          $ref: '#/components/schemas/hafbe_backend.order_by_proxy'
          default: proxy_date
        description: |
          Sort order:

           * `account` - delegator account name

           * `proxy_date` - block in which the proxy was set

           * `proxied_vests` - effective vested amount contributed via proxy
      - in: query
        name: direction
        required: false
        schema:
          $ref: '#/components/schemas/hafbe_backend.sort_direction'
          default: desc
        description: |
          Sort direction:

           * `asc` - Ascending, from A to Z or smallest to largest

           * `desc` - Descending, from Z to A or largest to smallest
    responses:
      '200':
        description: Array of delegators and their total vested power
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/hafbe_backend.array_of_proxy_power'
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
    "page" INT = 1,
    "sort" hafbe_backend.order_by_proxy = 'proxy_date',
    "direction" hafbe_backend.sort_direction = 'desc'
)
RETURNS SETOF hafbe_backend.proxy_power 
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
  _account_id INT := hafah_backend.get_account_id("account-name", TRUE);
  -- Normalize optional params: an explicit NULL must fall back to the signature default.
  -- PostgREST applies the default only when a param is OMITTED, not when it is explicitly
  -- null, so a raw NULL would otherwise reach the backend -- a NULL sort/direction collapses
  -- the ORDER BY CASE and silently DROPS the sort (arbitrary row order), and a NULL page
  -- slips past validate_negative_page (NULL <= 0 is NULL, not TRUE) into OFFSET NULL.
  _page      INT                          := COALESCE("page", 1);
  _sort      hafbe_backend.order_by_proxy := COALESCE("sort", 'proxy_date');
  _direction hafbe_backend.sort_direction := COALESCE("direction", 'desc');
BEGIN
  -- validate that page ≥ 1
  PERFORM hafbe_backend.validate_negative_page(_page);

  -- set short public cache
  PERFORM set_config(
    'response.headers',
    '[{"Cache-Control":"public, max-age=5"}]',
    true
  );

  -- delegate to ID-based backend logic
  RETURN QUERY
    SELECT *
      FROM hafbe_backend.get_account_proxies_power(
             _account_id,
             _page,
             _sort,
             _direction
           );
END;
$$;

RESET ROLE;
