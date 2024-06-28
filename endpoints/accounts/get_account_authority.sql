SET ROLE hafbe_owner;

/** openapi:paths
/accounts/{account-name}/authority:
  get:
    tags:
      - Accounts
    summary: Get account info
    description: |
      Get information about account's OWNER, ACTIVE, POSTING, memo and signing authorities

      SQL example
      * `SELECT * FROM hafbe_endpoints.get_account_authority('blocktrades');`

      * `SELECT * FROM hafbe_endpoints.get_account_authority('initminer');`

      REST call example
      * `GET https://{hafbe-host}/hafbe/accounts/blocktrades/authority`
      
      * `GET https://{hafbe-host}/hafbe/accounts/initminer/authority`
    operationId: hafbe_endpoints.get_account_authority
    parameters:
      - in: path
        name: account-name
        required: true
        schema:
          type: string
        description: Name of the account
    responses:
      '200':
        description: |
          List of account's authorities

          * Returns `hafbe_types.account_authority`
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/hafbe_types.account_authority'
            example:
              - owner: {
                    "key_auth":[
                        [
                          "STM7sw22HqsXbz7D2CmJfmMwt9rimtk518dRzsR1f8Cgw52dQR1pR",
                          "1"
                        ]
                      ],
                    "account_auth": [],
                    "weight_threshold": 1
                  }
                active: {
                    "key_auth":[
                        [
                          "STM7sw22HqsXbz7D2CmJfmMwt9rimtk518dRzsR1f8Cgw52dQR1pR",
                          "1"
                        ]
                      ],
                    "account_auth": [],
                    "weight_threshold": 1
                  }
                posting: {
                    "key_auth":[
                        [
                          "STM7sw22HqsXbz7D2CmJfmMwt9rimtk518dRzsR1f8Cgw52dQR1pR",
                          "1"
                        ]
                      ],
                    "account_auth": [],
                    "weight_threshold": 1
                  }
                memo: STM78Vaf41p9UUMMJvafLTjMurnnnuAiTqChiT5GBph7VDWahQRsz
                witness_signing: STM776t8h7dXbvM8BYGoLjCr3nYRnmqmvVg9hTrGTn5FQvLkMZKM2
      '404':
        description: No such account in the database
 */
-- openapi-generated-code-begin
DROP FUNCTION IF EXISTS hafbe_endpoints.get_account_authority;
CREATE OR REPLACE FUNCTION hafbe_endpoints.get_account_authority(
    "account-name" TEXT
)
RETURNS hafbe_types.account_authority 
-- openapi-generated-code-end
LANGUAGE 'plpgsql'
STABLE
SET JIT = OFF
SET join_collapse_limit = 16
SET from_collapse_limit = 16
AS
$$
BEGIN

-- 2s because this endpoint result is live account parameters and balances 
PERFORM set_config('response.headers', '[{"Cache-Control": "public, max-age=2"}]', true);

RETURN (
  WITH get_account_id AS
  (
    SELECT av.id FROM hive.accounts_view av WHERE av.name = "account-name"
  ),
  authorities AS
  (
    SELECT
      hafbe_backend.get_account_authority(gai.id, 'OWNER') AS owner,
      hafbe_backend.get_account_authority(gai.id, 'ACTIVE') AS active,
      hafbe_backend.get_account_authority(gai.id, 'POSTING') AS posting,   
      hafbe_backend.get_account_memo(gai.id) AS memo,
      hafbe_backend.get_account_witness_signing(gai.id) AS signing
    FROM get_account_id gai
  )
  SELECT ROW(
    to_json(a.owner),
    to_json(a.active),
    to_json(a.posting),
    a.memo,
    a.signing)
  FROM authorities a
);

END
$$;

RESET ROLE;
