SET ROLE hafbe_owner;

-- Witness page endpoint
/** openapi:paths
/witnesses/{account-name}:
  get:
    tags:
      - Witnesses
    summary: Returns information about a witness.
    description: |
      Returns information about a witness given their account name.

      SQL example
      * `SELECT * FROM hafbe_endpoints.get_witness(''blocktrades'');`
      
      REST call example
      * `GET ''https://%1$s/hafbe-api/witnesses/blocktrades''`
    operationId: hafbe_endpoints.get_witness
    parameters:
      - in: path
        name: account-name
        required: true
        schema:
          type: string
        description: witness account name
    responses:
      '200':
        description: |
          Various witness statistics

          * Returns `hafbe_types.witness_return`
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/hafbe_types.witness'
            example: {
              "witness_name": "blocktrades",
              "rank": 8,
              "url": "https://blocktrades.us",
              "vests": "82373419958692803",
              "votes_daily_change": "0",
              "voters_num": 263,
              "voters_num_daily_change": 0,
              "price_feed": 0.545,
              "bias": 0,
              "feed_updated_at": "2016-09-15T16:02:21",
              "block_size": 65536,
              "signing_key": "STM4vmVc3rErkueyWNddyGfmjmLs3Rr4i7YJi8Z7gFeWhakXM4nEz",
              "version": "0.13.0",
              "missed_blocks": 935,
              "hbd_interest_rate": 1000,
              "last_confirmed_block_num": 4999992,
              "account_creation_fee": 9000
            }
      '404':
        description: No such witness
*/
-- openapi-generated-code-begin
DROP FUNCTION IF EXISTS hafbe_endpoints.get_witness;
CREATE OR REPLACE FUNCTION hafbe_endpoints.get_witness(
    "account-name" TEXT
)
RETURNS hafbe_types.witness_return 
-- openapi-generated-code-end
LANGUAGE 'plpgsql'
STABLE
SET from_collapse_limit = 16
SET join_collapse_limit = 16
SET jit = OFF
AS
$$
DECLARE
  _witness_id INT = hafbe_backend.get_account_id("account-name");
  _result hafbe_types.witness;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM hafbe_app.current_witnesses WHERE witness_id = _witness_id) THEN
    PERFORM hafbe_exceptions.rest_raise_missing_witness("account-name");
  END IF;

  PERFORM set_config('response.headers', '[{"Cache-Control": "public, max-age=2"}]', true);

  RETURN hafbe_backend.get_witness(_witness_id);
END
$$;

RESET ROLE;
