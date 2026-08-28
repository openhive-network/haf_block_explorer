SET ROLE hafbe_owner;

-- ============================================================================
-- Sync Time Utilities
-- ============================================================================
-- Functions for tracking and logging processing times during block sync.
-- Used by the main processing loop to measure performance of each section.
--
-- USAGE:
--   DECLARE _time JSONB := '{}';
--   PERFORM hafbe_backend.get_sync_time(_time, 'time_on_start');  -- Start timer
--   -- ... processing ...
--   PERFORM hafbe_backend.get_sync_time(_time, 'section_name');   -- Log elapsed time
-- ============================================================================

/*
 * get_sync_time: Records timing information for sync processing sections.
 *
 * This function operates in two modes based on the _column_name:
 *   1. 'time_on_start': Initializes the timer by storing current timestamp
 *   2. Any other name: Calculates elapsed seconds since start and logs to NOTICE
 *
 * PARAMETERS:
 *   _time        - INOUT JSONB object accumulating timing data
 *   _column_name - Name of the timing metric to record
 *
 * RETURNS: Modified _time JSONB with the new timing entry
 *
 * DATA FLOW:
 *   1. If _column_name = 'time_on_start':
 *      - Stores current clock_timestamp() as starting point
 *   2. Otherwise:
 *      - Calculates seconds elapsed since time_on_start
 *      - Rounds to 3 decimal places
 *      - Outputs NOTICE message with section name and duration
 *      - Stores duration in _time JSONB under _column_name key
 *
 * EXAMPLE:
 *   Input:  _time = '{}', _column_name = 'time_on_start'
 *   Output: _time = '{"time_on_start": "2024-01-01 12:00:00"}'
 *
 *   Input:  _time = '{"time_on_start": "2024-01-01 12:00:00"}', _column_name = 'hafbe'
 *   Output: _time = '{"time_on_start": "2024-01-01 12:00:00", "hafbe": 1.234}'
 *           NOTICE: hafbe processed successfully. 1.234 seconds
 */
CREATE OR REPLACE FUNCTION hafbe_backend.get_sync_time(
    INOUT _time        JSONB,
          _column_name TEXT
)
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
    _time := jsonb_set(
      _time,
      __column_name,
      to_jsonb(
        ROUND(
          EXTRACT(epoch FROM (clock_timestamp() - (_time ->> 'time_on_start')::TIMESTAMP)),
          3
        )
      )
    );
    -- per-component timing of every range; recorded in hafbe_app.sync_time_logs, so keep
    -- it out of the block-processing log (one line per component per block at head)
    RAISE DEBUG '% processed successfully. % seconds', _column_name, _time ->> _column_name;
  END IF;
END
$$;

RESET ROLE;
