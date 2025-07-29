SET ROLE hafbe_owner;

/** openapi:paths
/accounts/{account-name}/authority:
  get:
    tags:
      - Accounts
    summary: Get account''s owner, active, posting, memo and witness signing authorities
    description: |
      Get information about account''s owner, active, posting, memo and witness signing authorities.

      SQL example
      * `SELECT * FROM hafbe_endpoints.get_account_authority(''blocktrades'');`

      REST call example
      * `GET ''https://%1$s/hafbe-api/accounts/blocktrades/authority''` 
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
          List of account''s authorities

          * Returns `hafbe_types.account_authority`
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/hafbe_types.account_authority'
            example: {
              "owner": {
                "key_auths": [
                  [
                    "STM7WdrxF6iuSiHUB4maoLGXXBKXbqAJ9AZbzACX1MPK2AkuCh23S",
                    "1"
                  ]
                ],
                "account_auths": [],
                "weight_threshold": 1
              },
              "active": {
                "key_auths": [
                  [
                    "STM5vgGoHBrUuDCspAPYi3dLwSyistyrz61NWkZNUAXAifZJaDLPF",
                    "1"
                  ]
                ],
                "account_auths": [],
                "weight_threshold": 1
              },
              "posting": {
                "key_auths": [
                  [
                    "STM5SaNVKJgy6ghnkNoMAprTxSDG55zps21Bo8qe1rnHmwAR4LzzC",
                    "1"
                  ]
                ],
                "account_auths": [],
                "weight_threshold": 1
              },
              "memo": "STM7EAUbNf1CdTrMbydPoBTRMG4afXCoAErBJYevhgne6zEP6rVBT",
              "witness_signing": "STM4vmVc3rErkueyWNddyGfmjmLs3Rr4i7YJi8Z7gFeWhakXM4nEz"
            }
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
DECLARE
  _account_id INT := hafah_backend.get_account_id("account-name", TRUE);
BEGIN
  -- 2s because this endpoint result is live account parameters and balances 
  PERFORM set_config('response.headers', '[{"Cache-Control": "public, max-age=2"}]', true);

  RETURN (
    hafbe_backend.get_account_authority(_account_id, 'OWNER'),
    hafbe_backend.get_account_authority(_account_id, 'ACTIVE'),
    hafbe_backend.get_account_authority(_account_id, 'POSTING'),   
    hafbe_backend.get_account_memo(_account_id),
    hafbe_backend.get_account_witness_signing(_account_id)
  )::hafbe_types.account_authority;

END
$$;

RESET ROLE;
