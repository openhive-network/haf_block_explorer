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
          default: all
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

          * Returns `hafbe_types.permlink_history`
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/hafbe_types.permlink_history'
            example: {
                "total_permlinks": 3,
                "total_pages": 2,
                "block_range": {
                  "from": 4000000,
                  "to": 4800000
                },
                "permlinks_result": [
                  {
                    "permlink": "witness-report-for-blocktrades-for-last-week-of-august",
                    "block": 4575065,
                    "trx_id": "d35590b9690ee8aa4b572901d62bc6263953346a",
                    "timestamp": "2016-09-01T00:18:51",
                    "operation_id": "19649754552074241"
                  },
                  {
                    "permlink": "blocktrades-witness-report-for-3rd-week-of-august",
                    "block": 4228346,
                    "trx_id": "bdcd754eb66f18eac11322310ae7ece1e951c08c",
                    "timestamp": "2016-08-19T21:27:00",
                    "operation_id": "18160607786173953"
                  }
                ]
              }
      '404':
        description: No such account in the database
 */
-- openapi-generated-code-begin
DROP FUNCTION IF EXISTS hafbe_endpoints.get_comment_permlinks;
CREATE OR REPLACE FUNCTION hafbe_endpoints.get_comment_permlinks(
    "account-name" TEXT,
    "comment-type" hafbe_types.comment_type = 'all',
    "page" INT = 1,
    "page-size" INT = 100,
    "from-block" TEXT = NULL,
    "to-block" TEXT = NULL
)
RETURNS hafbe_types.permlink_history 
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
  _account_id INT                := hafah_backend.get_account_id("account-name", TRUE);
  _block_range hive.blocks_range := hive.convert_to_blocks_range("from-block","to-block");
  _head_block_num INT            := hafbe_backend.get_haf_head_block();

  __block_range hafbe_backend.blocksearch_filter_return;
BEGIN
  PERFORM hafbe_exceptions.validate_limit("page-size", 100);
  PERFORM hafbe_exceptions.validate_negative_limit("page-size");
  PERFORM hafbe_exceptions.validate_negative_page("page");
  PERFORM hafbe_exceptions.validate_comment_search_indexes();
  PERFORM hafbe_exceptions.validate_block_num_too_high(_block_range.first_block, _head_block_num);

  IF _block_range.last_block <= hive.app_get_irreversible_block() AND _block_range.last_block IS NOT NULL THEN
    PERFORM set_config('response.headers', '[{"Cache-Control": "public, max-age=31536000"}]', true);
  ELSE
    PERFORM set_config('response.headers', '[{"Cache-Control": "public, max-age=2"}]', true);
  END IF;

  __block_range := hafbe_backend.blocksearch_range(_block_range.first_block, _block_range.last_block, _head_block_num);

  RETURN hafbe_backend.get_comment_permlinks(
    "account-name",
    "comment-type",
    "page",
    "page-size",
    __block_range.from_block,
    __block_range.to_block
  );

END
$$;

RESET ROLE;
