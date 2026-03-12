-- =============================================================================
-- Comment Operations Helper Functions
-- =============================================================================
-- Functions for retrieving operations related to a specific comment
-- (author + permlink combination). Used by the comment history endpoint.
-- =============================================================================

SET ROLE hafbe_owner;

/*
 * get_comment_operations: Retrieves operations for a specific comment.
 *
 * Returns paginated list of operations that affected a comment identified
 * by author and permlink. Operations are filtered by type and ordered by
 * operation ID.
 *
 * PARAMETERS:
 *   _author          - Comment author account name
 *   _permlink        - Comment permlink (unique per author)
 *   _operation_types - Array of operation type IDs to include
 *   _page_num        - Page number (1-based)
 *   _page_size       - Number of operations per page
 *   _order_is        - Sort direction ('asc' or 'desc')
 *   _body_limit      - Maximum length for operation body (0 = no limit)
 *
 * RETURNS: Set of operation records with full details
 *
 * NOTE: Uses enable_hashjoin = OFF to force nested loop joins which
 * perform better for this specific query pattern.
 */
CREATE OR REPLACE FUNCTION hafbe_backend.get_comment_operations(
    _author          TEXT,
    _permlink        TEXT,
    _operation_types INT[],
    _page_num        INT,
    _page_size       INT,
    _order_is        hafbe_backend.sort_direction,
    _body_limit      INT
)
RETURNS SETOF hafbe_backend.operation
LANGUAGE 'plpgsql' STABLE
SET enable_hashjoin = OFF
AS
$$
DECLARE
  __offset INT := ((_page_num - 1) * _page_size);
BEGIN
  RETURN QUERY
    /*
     * =========================================================================
     * CTE: operation_range
     * =========================================================================
     * PURPOSE: Find all operations matching the author/permlink with pagination.
     *
     * Filters by:
     *   - Operation type (must be in provided array)
     *   - Author field in operation body
     *   - Permlink field in operation body
     *
     * Applies pagination BEFORE joining for efficiency.
     */
    WITH operation_range AS (
      SELECT
        ov.block_num,
        ov.id,
        ov.body,
        ov.op_pos,
        ov.trx_in_block,
        ov.op_type_id
      FROM hive.operations_view ov
      WHERE
        ov.op_type_id = ANY(_operation_types) AND
        ov.body_value ->> 'author' = _author AND
        ov.body_value ->> 'permlink' = _permlink
      ORDER BY
        (CASE WHEN _order_is = 'desc' THEN ov.id ELSE NULL END) DESC,
        (CASE WHEN _order_is = 'asc' THEN ov.id ELSE NULL END) ASC
      OFFSET __offset
      LIMIT _page_size
    ),

    /*
     * =========================================================================
     * CTE: join_transactions
     * =========================================================================
     * PURPOSE: Enrich operations with transaction hash, timestamp, and metadata.
     *
     * Joins:
     *   - transactions_view for trx_hash
     *   - blocks_view for created_at timestamp
     *   - operation_types for is_virtual flag
     */
    join_transactions AS (
      SELECT
        orr.body,
        orr.block_num,
        -- Subquery for trx_hash avoids full table scan
        (
          SELECT encode(trx_hash, 'hex')
          FROM hive.transactions_view
          WHERE block_num = orr.block_num AND trx_in_block = orr.trx_in_block
        ) AS trx_hash,
        orr.op_pos,
        orr.op_type_id,
        bv.created_at,
        hot.is_virtual,
        orr.id,
        orr.trx_in_block
      FROM operation_range orr
      JOIN hafd.operation_types hot ON hot.id = orr.op_type_id
      JOIN hive.blocks_view bv      ON bv.num = orr.block_num
    )

    /*
     * Apply body filtering using hafah_backend.operation_body_filter
     * to truncate large operation bodies if _body_limit is specified.
     */
    SELECT
      (filtered_operations.composite).body,
      filtered_operations.block_num,
      filtered_operations.trx_hash,
      filtered_operations.op_pos,
      filtered_operations.op_type_id,
      filtered_operations.created_at,
      filtered_operations.is_virtual,
      filtered_operations.id::TEXT,
      filtered_operations.trx_in_block::SMALLINT
    FROM (
      SELECT
        hafah_backend.operation_body_filter(jt.body, jt.id, _body_limit) AS composite,
        jt.block_num,
        jt.trx_hash,
        jt.op_pos,
        jt.op_type_id,
        jt.created_at,
        jt.is_virtual,
        jt.id,
        jt.trx_in_block
      FROM join_transactions jt
    ) filtered_operations
    ORDER BY
      (CASE WHEN _order_is = 'desc' THEN filtered_operations.id ELSE NULL END) DESC,
      (CASE WHEN _order_is = 'asc' THEN filtered_operations.id ELSE NULL END) ASC;
END
$$;

/*
 * get_comment_operations_count: Counts operations for a specific comment.
 *
 * PARAMETERS:
 *   _author          - Comment author account name
 *   _permlink        - Comment permlink (unique per author)
 *   _operation_types - Array of operation type IDs to include
 *
 * RETURNS: Total count of matching operations
 *
 * NOTE: Uses same filtering logic as get_comment_operations for consistency.
 */
CREATE OR REPLACE FUNCTION hafbe_backend.get_comment_operations_count(
    _author          TEXT,
    _permlink        TEXT,
    _operation_types INT[]
)
RETURNS BIGINT
LANGUAGE 'plpgsql' STABLE
SET enable_hashjoin = OFF
AS
$$
BEGIN
  RETURN (
    SELECT COUNT(*)
    FROM hive.operations_view ov
    WHERE
      ov.op_type_id = ANY(_operation_types) AND
      ov.body_value ->> 'author' = _author AND
      ov.body_value ->> 'permlink' = _permlink
  );
END
$$;

RESET ROLE;
