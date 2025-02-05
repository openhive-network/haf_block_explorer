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

          * Returns `JSON`
        content:
          application/json:
            schema:
              type: string
              x-sql-datatype: JSON
            example:      
              - {
                  "input_type": "account_name",
                  "input_value": "blocktrades"
                }
      '404':
        description: Input is not recognized
 */
-- openapi-generated-code-begin
-- openapi-generated-code-end
LANGUAGE 'plpgsql' STABLE
AS
$$
DECLARE
  __hash BYTEA;
  __block_num INT;
  __head_block_num INT;
  __accounts_array JSON;
BEGIN
  -- names in db are lowercase, no uppercase is used in hashes
  SELECT lower("input-value") INTO "input-value";

  -- first, name existance is checked
  IF (SELECT 1 FROM hive.accounts_view WHERE name = "input-value" LIMIT 1) IS NOT NULL THEN

    PERFORM set_config('response.headers', '[{"Cache-Control": "public, max-age=31536000"}]', true);

    RETURN json_build_object(
      'input_type', 'account_name',
      'input_value', "input-value"
    );
  END IF;

  -- second, positive digit and not name is assumed to be block number
  IF "input-value" SIMILAR TO '(\d+)' THEN
    SELECT bv.num INTO __head_block_num FROM hive.blocks_view bv ORDER BY bv.num DESC LIMIT 1;
    IF "input-value"::NUMERIC > __head_block_num THEN

      PERFORM set_config('response.headers', '[{"Cache-Control": "public, max-age=2"}]', true);

      RETURN hafbe_exceptions.raise_block_num_too_high_exception("input-value"::NUMERIC, __head_block_num);
    ELSE

      PERFORM set_config('response.headers', '[{"Cache-Control": "public, max-age=31536000"}]', true);

      RETURN json_build_object(
        'input_type', 'block_num',
        'input_value', "input-value"
      );
    END IF;
  END IF;

  -- third, if input is 40 char hash, it is validated for transaction or block hash
  -- hash is unknown if failed to validate
  IF "input-value" SIMILAR TO '([a-f0-9]{40})' THEN
    SELECT ('\x' || "input-value")::BYTEA INTO __hash;
    
    IF (SELECT trx_hash FROM hive.transactions_view WHERE trx_hash = __hash LIMIT 1) IS NOT NULL THEN

      PERFORM set_config('response.headers', '[{"Cache-Control": "public, max-age=31536000"}]', true);

      RETURN json_build_object(
        'input_type', 'transaction_hash',
        'input_value', "input-value"
      );
    ELSE
      SELECT bv.num 
      FROM hive.blocks_view bv
      WHERE bv.hash = __hash LIMIT 1 
      INTO __block_num;
    END IF;

    IF __block_num IS NOT NULL THEN

      PERFORM set_config('response.headers', '[{"Cache-Control": "public, max-age=31536000"}]', true);

      RETURN json_build_object(
        'input_type', 'block_hash',
        'input_value', __block_num
      );
    ELSE

      PERFORM set_config('response.headers', '[{"Cache-Control": "public, max-age=2"}]', true);

      RETURN hafbe_exceptions.raise_unknown_hash_exception("input-value");
    END IF;
  END IF;

  -- fourth, it is still possible input is partial name, max 50 names returned.
  -- if no matching accounts were found, 'unknown_input' is returned
  SELECT json_agg(account_query.accounts
    ORDER BY
      account_query.name_lengths,
      account_query.accounts)
  INTO __accounts_array
  FROM (
    SELECT
      ha.name AS accounts,
      LENGTH(ha.name) AS name_lengths
    FROM
      hive.accounts_view ha
    WHERE
      ha.name LIKE "input-value" || '%'
    ORDER BY
      accounts,
      name_lengths
    LIMIT 50
  ) account_query;

  IF __accounts_array IS NOT NULL THEN

    PERFORM set_config('response.headers', '[{"Cache-Control": "public, max-age=31536000"}]', true);

    RETURN json_build_object(
      'input_type', 'account_name_array',
      'input_value', __accounts_array
    );
  ELSE

    PERFORM set_config('response.headers', '[{"Cache-Control": "public, max-age=2"}]', true);

    RETURN json_build_object(
        'input_type', 'invalid_input',
        'input_value', "input-value"
      );
  END IF;
END
$$;

RESET ROLE;
