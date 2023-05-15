CREATE OR REPLACE FUNCTION hafbe_app.process_block_range_data_c(_first_block INT, _last_block INT)
RETURNS VOID
LANGUAGE plpgsql;
AS
$function$
DECLARE
    _raw_op RECORD;
BEGIN
    -- get all raw operations
    FOR _raw_op IN
        SELECT
            ov.id,
            ov.op_type_id,
            ov.block_num,
            ov.timestamp,
            ov.trx_in_block,
            tv.trx_hash,
            ov.body::varchar::jsonb
        FROM hive.hafbe_app_operations_view ov
        LEFT JOIN hive.transactions_view tv
            ON tv.block_num = ov.block_num
            AND tv.trx_in_block = ov.trx_in_block
        WHERE ov.block_num >= _first_block
            AND ov.block_num <= _last_block
        ORDER BY ov.block_num, ov.id
    LOOP
        -- process operation
        PERFORM hafbe_app.process_operation(_raw_op);
        _last_block_timestamp := _raw_op.timestamp;
    END LOOP;
END;
$function$

CREATE OR REPLACE FUNCTION hafbe_app.process_operation(_raw_op RECORD)
    RETURNS VOID
    LANGUAGE plpgsql;
    AS $function$
    DECLARE
        tempnotif JSONB;
        _module_schema VARCHAR;
    BEGIN
        IF _raw_op.op_type_id = 12 THEN
            PERFORM hafbe_app.account_witness_vote(_raw_op.block_num, _raw_op.timestamp, _raw_op.trx_hash, _raw_op.body);
        ELSIF _raw_op.op_type_id = 13 THEN
            PERFORM hafbe_app.account_witness_proxy(_raw_op.block_num, _raw_op.timestamp, _raw_op.trx_hash, _raw_op.body);
        ELSIF _raw_op.op_type_id = 91 THEN
            PERFORM hafbe_app.account_proxy_cleared(_raw_op.block_num, _raw_op.timestamp, _raw_op.trx_hash, _raw_op.body);
        ELSIF _raw_op.op_type_id = 11 THEN
            PERFORM hafbe_app.witness_update(_raw_op.block_num, _raw_op.timestamp, _raw_op.trx_hash, _raw_op.body);
        END IF;
    END;
    $function$