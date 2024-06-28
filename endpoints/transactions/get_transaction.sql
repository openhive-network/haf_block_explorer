SET ROLE hafbe_owner;


/** openapi:paths
/transactions/{transaction-id}:
  get:
    tags:
      - Transactions
    summary: Get transaction info
    description: |
      Get information about transaction 

      SQL example
      * `SELECT * FROM hafbe_endpoints.get_transaction('954f6de36e6715d128fa8eb5a053fc254b05ded0');`
      
      REST call example
      * `GET https://{hafbe-host}/hafbe/transactions/954f6de36e6715d128fa8eb5a053fc254b05ded0`
    operationId: hafbe_endpoints.get_transaction
    parameters:
      - in: path
        name: transaction-id
        required: true
        schema:
          type: string
        description: The transaction hash
    responses:
      '200':
        description: |
          The transaction body

          * Returns `hafbe_types.transaction`
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/hafbe_types.transaction'
            example:
              - transaction_json: {
                    "ref_block_num": 25532,
                    "ref_block_prefix": 3338687976,
                    "extensions": [],
                    "expiration": "2016-08-12T17:23:48",
                    "operations": [
                      {
                        "type": "custom_json_operation",
                        "value": {
                          "id": "follow",
                          "json": "{\"follower\":\"breck0882\",\"following\":\"steemship\",\"what\":[]}",
                          "required_auths": [],
                          "required_posting_auths": [
                            "breck0882"
                          ]
                        }
                      }
                    ],
                    "signatures": [
                      "201655190aac43bb272185c577262796c57e5dd654e3e491b921a38697d04d1a8e6a9deb722ec6d6b5d2f395dcfbb94f0e5898e858f"
                    ]
                  }
                transaction_id: 954f6de36e6715d128fa8eb5a053fc254b05ded0
                block_num: 4023233
                transaction_num: 0
                timestamp: '2016-08-12T17:23:39'
                age: '2852 days 15:46:22.097754'
      '404':
        description: No such transaction
 */
-- openapi-generated-code-begin
DROP FUNCTION IF EXISTS hafbe_endpoints.get_transaction;
CREATE OR REPLACE FUNCTION hafbe_endpoints.get_transaction(
    "transaction-id" TEXT
)
RETURNS hafbe_types.transaction 
-- openapi-generated-code-end
LANGUAGE 'plpgsql' STABLE
AS
$$
DECLARE
 _get_transaction hafbe_types.transaction;
BEGIN
WITH select_transaction AS MATERIALIZED 
(
SELECT transaction_json::JSON,
bv.created_at,
NOW() - bv.created_at
-- _trx_hash TEXT -> BYTEA, __include_reversible = TRUE, __is_legacy_style = FALSE
FROM hafah_python.get_transaction_json(('\x' || "transaction-id")::BYTEA, TRUE, FALSE) AS transaction_json
JOIN hive.blocks_view bv ON bv.num = (transaction_json->>'block_num')::INT
)
SELECT 
	json_build_object(
	'ref_block_num', (transaction_json->>'ref_block_num')::BIGINT,
	'ref_block_prefix',(transaction_json->>'ref_block_prefix')::BIGINT,
	'extensions', (transaction_json->>'extensions')::JSON,
	'expiration', transaction_json->>'expiration',
	'operations', (transaction_json->>'operations')::JSON,
	'signatures', (transaction_json->>'signatures')::JSON
	),
	transaction_json->>'transaction_id',
	(transaction_json->>'block_num')::INT,
	(transaction_json->>'transaction_num')::INT,
	created_at,
	NOW() - created_at INTO _get_transaction
FROM select_transaction;
 
IF _get_transaction.block_num <= hive.app_get_irreversible_block() THEN
  PERFORM set_config('response.headers', '[{"Cache-Control": "public, max-age=31536000"}]', true);
ELSE
  PERFORM set_config('response.headers', '[{"Cache-Control": "public, max-age=2"}]', true);
END IF;

RETURN _get_transaction;

END
$$;

RESET ROLE;
