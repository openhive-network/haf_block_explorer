SET ROLE hafbe_owner;

/** openapi:paths
/input-type/{input-value}:
  get:
    tags:
      - Other
    summary: Determines object type of input-value.
    description: |
      Determines whether the entered value is a block,
      block hash, transaction hash, or account name.
      This method is very specific to block explorer UIs.

      SQL example
      * `SELECT * FROM hafbe_endpoints.get_input_type(''blocktrades'');`
            
      REST call example
      * `GET ''https://%1$s/hafbe-api/input-type/blocktrades''`
    operationId: hafbe_endpoints.get_input_type
    parameters:
      - in: path
        name: input-value
        required: true
        schema:
          type: string
        description: Object type to be identified.
    responses:
      '200':
        description: |
          Result contains total operations number,
          total pages and the list of operations

          * Returns `hafbe_types.input_type_return `
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/hafbe_types.input_type_return'
            example: {
                  "input_type": "account_name",
                  "input_value": [
                    "blocktrades"
                  ]
                }
      '404':
        description: Input is not recognized
 */
-- openapi-generated-code-begin
DROP FUNCTION IF EXISTS hafbe_endpoints.get_input_type;
CREATE OR REPLACE FUNCTION hafbe_endpoints.get_input_type(
    "input-value" TEXT
)
RETURNS hafbe_types.input_type_return 
-- openapi-generated-code-end
LANGUAGE 'plpgsql' STABLE
AS
$$
DECLARE
  __hash BYTEA;
  __block_num INT;
  __head_block_num INT;
  __accounts_array TEXT[];
  __input_value TEXT;
BEGIN
  -- names in db are lowercase, no uppercase is used in hashes
  SELECT lower("input-value") INTO __input_value;

  -- first, name existance is checked
  IF (SELECT 1 FROM hive.accounts_view WHERE name = __input_value LIMIT 1) IS NOT NULL THEN

    PERFORM set_config('response.headers', '[{"Cache-Control": "public, max-age=31536000"}]', true);

    RETURN (
      'account_name',
      ARRAY[__input_value]
    )::hafbe_types.input_type_return;
  END IF;

  -- second, positive digit and not name is assumed to be block number
  IF __input_value SIMILAR TO '(\d+)' THEN
    SELECT bv.num INTO __head_block_num FROM hive.blocks_view bv ORDER BY bv.num DESC LIMIT 1;
    IF __input_value::NUMERIC > __head_block_num THEN

      PERFORM set_config('response.headers', '[{"Cache-Control": "public, max-age=2"}]', true);

      PERFORM hafbe_exceptions.raise_block_num_too_high_exception(__input_value::NUMERIC, __head_block_num);
    ELSE

      PERFORM set_config('response.headers', '[{"Cache-Control": "public, max-age=31536000"}]', true);

      RETURN (
        'block_num',
        ARRAY[__input_value]
      )::hafbe_types.input_type_return;

    END IF;
  END IF;

  -- third, if input is 40 char hash, it is validated for transaction or block hash
  -- hash is unknown if failed to validate
  IF __input_value SIMILAR TO '([a-f0-9]{40})' THEN
    SELECT ('\x' || __input_value)::BYTEA INTO __hash;
    
    IF (SELECT trx_hash FROM hive.transactions_view WHERE trx_hash = __hash LIMIT 1) IS NOT NULL THEN

      PERFORM set_config('response.headers', '[{"Cache-Control": "public, max-age=31536000"}]', true);

      RETURN (
        'transaction_hash',
        ARRAY[__input_value]
      )::hafbe_types.input_type_return;

    ELSE
      SELECT bv.num 
      FROM hive.blocks_view bv
      WHERE bv.hash = __hash LIMIT 1 
      INTO __block_num;
    END IF;

    IF __block_num IS NOT NULL THEN

      PERFORM set_config('response.headers', '[{"Cache-Control": "public, max-age=31536000"}]', true);

      RETURN (
        'block_hash',
        ARRAY[__block_num::TEXT]
      )::hafbe_types.input_type_return;

    ELSE

      PERFORM set_config('response.headers', '[{"Cache-Control": "public, max-age=2"}]', true);

      PERFORM hafbe_exceptions.raise_unknown_hash_exception(__input_value);
    END IF;
  END IF;

  -- fourth, it is still possible input is partial name, max 50 names returned.
  -- if no matching accounts were found, 'unknown_input' is returned
  SELECT array_agg(account_query.accounts
    ORDER BY
      account_query.name_lengths,
      account_query.accounts
  )
  INTO __accounts_array
  FROM (
    SELECT
      ha.name AS accounts,
      LENGTH(ha.name) AS name_lengths
    FROM
      hive.accounts_view ha
    WHERE
      ha.name LIKE __input_value || '%'
    ORDER BY
      accounts,
      name_lengths
    LIMIT 50
  ) account_query;

  IF __accounts_array IS NOT NULL THEN

    PERFORM set_config('response.headers', '[{"Cache-Control": "public, max-age=31536000"}]', true);

    RETURN (
      'account_name_array',
      __accounts_array
    )::hafbe_types.input_type_return;

  ELSE

    PERFORM set_config('response.headers', '[{"Cache-Control": "public, max-age=2"}]', true);

    RETURN (
      'invalid_input',
      ARRAY[__input_value]
    )::hafbe_types.input_type_return;

  END IF;
END
$$;

RESET ROLE;
