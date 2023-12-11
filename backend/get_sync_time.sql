SET ROLE hafbe_owner;

-- Used in sync
CREATE OR REPLACE FUNCTION hafbe_backend.get_sync_time(INOUT _time JSONB, _column_name TEXT)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
    __column_name TEXT[] := '{' || _column_name || '}';
BEGIN
    IF __column_name = '{time_on_start}' THEN
        _time := jsonb_set(_time, __column_name, to_jsonb(clock_timestamp()));
    ELSE
        _time := jsonb_set(_time, __column_name, to_jsonb(ROUND(EXTRACT(epoch FROM (clock_timestamp()- (_time->>'time_on_start')::TIMESTAMP)),3)));
        RAISE NOTICE '% processed successfully. % seconds', _column_name, _time ->>_column_name;
    END IF;
END
$$;

RESET ROLE;
