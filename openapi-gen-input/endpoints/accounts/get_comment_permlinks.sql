SET ROLE hafbe_owner;

/** openapi:paths
/accounts/{account-name}/comment-permlinks:
  get:
    tags:
      - Accounts
    summary: Get comment permlinks for an account.
    description: |
      List comment permlinks of root posts or comments for an account.

      SQL example
      * `SELECT * FROM hafbe_endpoints.get_comment_permlinks(''blocktrades'',''post'',1,2,''4000000'',''4800000'');`

      REST call example
      * `GET ''https://%1$s/hafbe-api/accounts/blocktrades/comment-permlinks?comment-type=post&page-size=2&from-block=4000000&to-block=4800000''`
    operationId: hafbe_endpoints.get_comment_permlinks
    parameters:
      - in: path
        name: account-name
        required: true
        schema:
          type: string
        description: Account to get operations for
      - in: query
        name: comment-type
        required: false
        schema:
          $ref: '#/components/schemas/hafbe_types.comment_type'
          default: post
        description: |
          Sort order:
          
           * `post`    - permlinks related to root posts

           * `comment` - permlinks related to comments 

           * `all`     - both, posts and comments
      - in: query
        name: page
        required: false
        schema:
          type: integer
          default: 1
        description: Return page on `page` number, defaults to `1`
      - in: query
        name: page-size
        required: false
        schema:
          type: integer
          default: 100
        description: Return max `page-size` operations per page, defaults to `100`
      - in: query
        name: from-block
        required: false
        schema:
          type: string
          default: NULL
        description: |
          Lower limit of the block range, can be represented either by a block-number (integer) or a timestamp (in the format YYYY-MM-DD HH:MI:SS).

          The provided `timestamp` will be converted to a `block-num` by finding the first block 
          where the block''s `created_at` is more than or equal to the given `timestamp` (i.e. `block''s created_at >= timestamp`).

          The function will interpret and convert the input based on its format, example input:

          * `2016-09-15 19:47:21`

          * `5000000`
      - in: query
        name: to-block
        required: false
        schema:
          type: string
          default: NULL
        description: | 
          Similar to the from-block parameter, can either be a block-number (integer) or a timestamp (formatted as YYYY-MM-DD HH:MI:SS). 

          The provided `timestamp` will be converted to a `block-num` by finding the first block 
          where the block''s `created_at` is less than or equal to the given `timestamp` (i.e. `block''s created_at <= timestamp`).
          
          The function will convert the value depending on its format, example input:

          * `2016-09-15 19:47:21`

          * `5000000`
    responses:
      '200':
        description: |
          Result contains total number of operations,
          total pages, and the list of operations.

          * Returns `JSON`
        content:
          application/json:
            schema:
              type: string
              x-sql-datatype: JSON
            example:  
              - {
                  "total_operations": 3,
                  "total_pages": 2,
                  "operations_result": [
                    {
                      "permlink": "blocktrades-witness-report-for-3rd-week-of-august",
                      "block": 4228346,
                      "trx_id": "bdcd754eb66f18eac11322310ae7ece1e951c08c",
                      "timestamp": "2016-08-19T21:27:00",
                      "operation_id": "18160607786173953"
                    },
                    {
                      "permlink": "blocktrades-witness-report-for-2nd-week-of-august",
                      "block": 4024774,
                      "trx_id": "82a2a959b0087f1eb8f38512b032d8468f194154",
                      "timestamp": "2016-08-12T18:40:42",
                      "operation_id": "17286272703793409"
                    }
                  ]
                }
      '404':
        description: No such account in the database
 */
-- openapi-generated-code-begin
-- openapi-generated-code-end
LANGUAGE 'plpgsql' STABLE
SET join_collapse_limit = 16
SET from_collapse_limit = 16
SET JIT = OFF
SET enable_hashjoin = OFF
SET plan_cache_mode = force_custom_plan -- FIXME
AS
$$
DECLARE
  _block_range hive.blocks_range := hive.convert_to_blocks_range("from-block","to-block");
  _calculate_total_pages INT;
  _ops_count INT;
BEGIN

PERFORM hafbe_exceptions.validate_limit("page-size", 100);
PERFORM hafbe_exceptions.validate_negative_limit("page-size");
PERFORM hafbe_exceptions.validate_negative_page("page");

IF NOT hafbe_app.isCommentSearchIndexesCreated() THEN
  RAISE EXCEPTION 'Commentsearch indexes are not installed';
END IF;

IF _block_range.last_block <= hive.app_get_irreversible_block() AND _block_range.last_block IS NOT NULL THEN
  PERFORM set_config('response.headers', '[{"Cache-Control": "public, max-age=31536000"}]', true);
ELSE
  PERFORM set_config('response.headers', '[{"Cache-Control": "public, max-age=2"}]', true);
END IF;

--count for given parameters 
SELECT hafbe_backend.get_comment_permlinks_count(
  "account-name",
  "comment-type",
  _block_range.first_block,
  _block_range.last_block
) INTO _ops_count;

--amount of pages
SELECT (
  CASE WHEN (_ops_count % "page-size") = 0 THEN 
    _ops_count/"page-size" 
  ELSE ((_ops_count/"page-size") + 1) 
  END
)::INT INTO _calculate_total_pages;

PERFORM hafbe_exceptions.validate_page("page", _calculate_total_pages);

RETURN (
  SELECT json_build_object(
    'total_permlinks', _ops_count,
    'total_pages', _calculate_total_pages,
    'permlinks_result', 
    (SELECT COALESCE(to_json(array_agg(row)), '[]') FROM (
      SELECT * FROM hafbe_backend.get_comment_permlinks(
        "account-name",
        "comment-type",
        "page",
        "page-size",
        _block_range.first_block,
        _block_range.last_block
      )
    ) row)
  ));

END
$$;

RESET ROLE;
