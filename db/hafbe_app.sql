CREATE SCHEMA IF NOT EXISTS hafbe_app;

CREATE OR REPLACE FUNCTION hafbe_app.define_schema()
RETURNS VOID
LANGUAGE 'plpgsql'
AS
$$
BEGIN
  RAISE NOTICE 'Attempting to create an application schema tables...';

  CREATE TABLE IF NOT EXISTS hafbe_app.app_status (
    continue_processing BOOLEAN,
    last_processed_block INT
  );
  INSERT INTO hafbe_app.app_status (continue_processing, last_processed_block)
  VALUES (True, 0);

  CREATE TABLE IF NOT EXISTS hafbe_app.witness_votes_history (
    witness_id INT NOT NULL,
    voter_id INT NOT NULL,
    approve BOOLEAN NOT NULL,
    timestamp TIMESTAMP NOT NULL
  ) INHERITS (hive.hafbe_app);

  CREATE INDEX IF NOT EXISTS witness_votes_history_witness_id ON hafbe_app.witness_votes_history USING btree (witness_id);
  CREATE INDEX IF NOT EXISTS witness_votes_history_voter_id ON hafbe_app.witness_votes_history USING btree (voter_id);
  CREATE INDEX IF NOT EXISTS witness_votes_history_timestamp ON hafbe_app.witness_votes_history USING btree (timestamp);

  CREATE TABLE IF NOT EXISTS hafbe_app.current_witness_votes (
    witness_id INT NOT NULL,
    voter_id INT NOT NULL,
    approve BOOLEAN NOT NULL,
    timestamp TIMESTAMP NOT NULL,

    CONSTRAINT pk_current_witness_votes PRIMARY KEY (witness_id, voter_id)
  ) INHERITS (hive.hafbe_app);

  CREATE INDEX IF NOT EXISTS current_witness_votes_approve ON hafbe_app.current_witness_votes USING btree (approve);
  CREATE INDEX IF NOT EXISTS current_witness_votes_timestamp ON hafbe_app.current_witness_votes USING btree (timestamp);

  CREATE TABLE IF NOT EXISTS hafbe_app.account_proxies_history (
    account_id INT NOT NULL,
    proxy_id INT,
    proxy BOOLEAN,
    timestamp TIMESTAMP NOT NULL
  ) INHERITS (hive.hafbe_app);

  CREATE INDEX IF NOT EXISTS account_proxies_history_account_id ON hafbe_app.account_proxies_history USING btree (account_id);
  CREATE INDEX IF NOT EXISTS account_proxies_history_proxy_id ON hafbe_app.account_proxies_history USING btree (proxy_id);
  CREATE INDEX IF NOT EXISTS account_proxies_history_timestamp ON hafbe_app.account_proxies_history USING btree (timestamp);

  CREATE TABLE IF NOT EXISTS hafbe_app.current_account_proxies (
    account_id INT NOT NULL,
    proxy_id INT,
    proxy BOOLEAN NOT NULL,

    CONSTRAINT pk_current_account_proxies PRIMARY KEY (account_id, proxy_id)
  ) INHERITS (hive.hafbe_app);

  CREATE INDEX IF NOT EXISTS current_account_proxies_proxy ON hafbe_app.current_account_proxies USING btree (proxy);

  CREATE TABLE IF NOT EXISTS hafbe_app.hived_account_cache (
    account TEXT NOT NULL,
    data JSON NOT NULL,

    CONSTRAINT pk_hived_account_cache PRIMARY KEY (account)
  );

  CREATE TABLE IF NOT EXISTS hafbe_app.account_operation_cache (
    account_id INT NOT NULL,
    op_type_id INT NOT NULL,

    CONSTRAINT pk_account_operation_cache PRIMARY KEY (account_id, op_type_id)
  ) INHERITS (hive.hafbe_app);

  CREATE TABLE IF NOT EXISTS hafbe_app.account_vests (
    account_id INT NOT NULL,
    vests BIGINT NOT NULL,

    CONSTRAINT pk_account_vests_account PRIMARY KEY (account_id)
  ) INHERITS (hive.hafbe_app);

  --ALTER SCHEMA hafbe_app OWNER TO hafbe_owner;
END
$$
;

--- Helper function telling application main-loop to continue execution.
CREATE OR REPLACE FUNCTION hafbe_app.continueProcessing()
RETURNS BOOLEAN
LANGUAGE 'plpgsql'
AS
$$
BEGIN
  RETURN continue_processing FROM hafbe_app.app_status LIMIT 1;
END
$$
;

CREATE OR REPLACE FUNCTION hafbe_app.allowProcessing()
RETURNS VOID
LANGUAGE 'plpgsql'
AS
$$
BEGIN
  UPDATE hafbe_app.app_status SET continue_processing = True;
END
$$
;

--- Helper function to be called from separate transaction (must be committed) to safely stop execution of the application.
CREATE OR REPLACE FUNCTION hafbe_app.stopProcessing()
RETURNS VOID
LANGUAGE 'plpgsql'
AS
$$
BEGIN
  UPDATE hafbe_app.app_status SET continue_processing = False;
END
$$
;

CREATE OR REPLACE FUNCTION hafbe_app.storeLastProcessedBlock(_lastBlock INT)
RETURNS VOID
LANGUAGE 'plpgsql'
AS
$$
BEGIN
  UPDATE hafbe_app.app_status SET last_processed_block = _lastBlock;
END
$$
;

CREATE OR REPLACE FUNCTION hafbe_app.lastProcessedBlock()
RETURNS INT
LANGUAGE 'plpgsql'
AS
$$
BEGIN
  RETURN last_processed_block FROM hafbe_app.app_status LIMIT 1;
END
$$
;

CREATE OR REPLACE FUNCTION hafbe_app.get_account_id(_account TEXT)
RETURNS INT
LANGUAGE 'plpgsql'
AS
$$
BEGIN
  RETURN id FROM hive.btracker_app_accounts_view WHERE name = _account;
END
$$
;

CREATE OR REPLACE FUNCTION hafbe_app.process_block_range_data_c(_from INT, _to INT, _report_step INT = 1000)
RETURNS VOID
LANGUAGE 'plpgsql'
AS
$$
DECLARE
  __last_reported_block INT := 0;
  __unproxy_op RECORD;
  __last_op_time TIMESTAMP;
  __balance_change RECORD;
  __hardfork_one_block_num INT = 905693;
BEGIN
  SELECT INTO __last_op_time CASE WHEN timestamp IS NULL THEN to_timestamp(0) ELSE timestamp END
  FROM hafbe_app.account_proxies_history ORDER BY timestamp DESC LIMIT 1;

  -- main processing loop
  FOR b IN _from .. _to
  LOOP
    INSERT INTO hafbe_app.witness_votes_history (witness_id, voter_id, approve, timestamp)
    SELECT
      hafbe_app.get_account_id((body::JSON)->'value'->>'witness'),
      hafbe_app.get_account_id((body::JSON)->'value'->>'account'),
      ((body::JSON)->'value'->>'approve')::BOOLEAN,
      timestamp
    FROM hive.btracker_app_operations_view
    WHERE op_type_id = 12 AND block_num = b;

    INSERT INTO hafbe_app.current_witness_votes (witness_id, voter_id, approve, timestamp)
    SELECT witness_id, voter_id, approve, timestamp
    FROM (
      SELECT
        -- must take latest op in block, in case voter does vote/unvote on same block
        ROW_NUMBER() OVER (PARTITION BY witness_id, voter_id ORDER BY timestamp DESC) AS row_n,
        witness_id, voter_id, approve, timestamp
      FROM (
        SELECT
          hafbe_app.get_account_id((body::JSON)->'value'->>'witness') AS witness_id,
          hafbe_app.get_account_id((body::JSON)->'value'->>'account') AS voter_id,
          ((body::JSON)->'value'->>'approve')::BOOLEAN AS approve,
          timestamp
        FROM hive.btracker_app_operations_view
        WHERE op_type_id = 12 AND block_num = b
      ) cur_votes
    ) row_count
    WHERE row_n = 1 AND approve = TRUE
    
    ON CONFLICT ON CONSTRAINT pk_current_witness_votes DO UPDATE SET
      witness_id = EXCLUDED.witness_id,
      voter_id = EXCLUDED.voter_id,
      approve = EXCLUDED.approve,
      timestamp = EXCLUDED.timestamp
    ;
    
    INSERT INTO hafbe_app.account_proxies_history (account_id, proxy_id, proxy, timestamp)
    SELECT
      account_id, proxy_id,
      CASE WHEN proxy_id IS NULL THEN FALSE ELSE TRUE END,
      timestamp
    FROM (
      SELECT
        hafbe_app.get_account_id(proxy_operation->>'account') AS account_id,
        hafbe_app.get_account_id(proxy_operation->>'proxy') AS proxy_id,
        timestamp
      FROM (
        SELECT
          (body::JSON)->'value' AS proxy_operation,
          timestamp
        FROM hive.btracker_app_operations_view
        WHERE op_type_id = 13 AND block_num = b
      ) hov
    ) acc_ids;
  
    INSERT INTO hafbe_app.account_operation_cache (account_id, op_type_id)
    SELECT account_id, op_type_id
    FROM hive.btracker_app_account_operations_view
    WHERE block_num = b
    ON CONFLICT ON CONSTRAINT pk_account_operation_cache DO NOTHING;
  END LOOP;

  -- postprocessing to fill null values of proxy_id when account does unproxy
  FOR __unproxy_op IN
    SELECT account_id, timestamp
    FROM hafbe_app.account_proxies_history
    WHERE timestamp > __last_op_time AND proxy_id IS NULL
  LOOP
    UPDATE hafbe_app.account_proxies_history
    SET proxy_id = (
      SELECT proxy_id
      FROM hafbe_app.account_proxies_history
      WHERE timestamp < __unproxy_op.timestamp AND account_id = __unproxy_op.account_id AND proxy_id IS NOT NULL
      ORDER BY timestamp DESC
      LIMIT 1
    )
    WHERE account_id = __unproxy_op.account_id AND proxy_id IS NULL;
  END LOOP;

  -- create data from account_proxies_history, after null values are filled
  INSERT INTO hafbe_app.current_account_proxies (account_id, proxy_id, proxy)
  SELECT account_id, proxy_id, proxy
  FROM (
    SELECT
      ROW_NUMBER() OVER (PARTITION BY account_id, proxy_id ORDER BY timestamp DESC) AS row_n,
      account_id, proxy_id, proxy
    FROM hafbe_app.account_proxies_history
    WHERE timestamp > __last_op_time
  ) row_count
  WHERE row_n = 1 AND proxy = TRUE
  ON CONFLICT ON CONSTRAINT pk_current_account_proxies DO UPDATE SET
    account_id = EXCLUDED.account_id,
    proxy_id = EXCLUDED.proxy_id,
    proxy = EXCLUDED.proxy
  ;

  -- get impacted vests balance for block range and update account_vests
  FOR __balance_change IN
    WITH balance_impacting_ops AS (
      SELECT hot.id
      FROM hive.operation_types hot
      WHERE hot.name IN (SELECT * FROM hive.get_balance_impacting_operations())
    )

    SELECT bio.account_name AS account, bio.amount AS vests
    FROM hive.btracker_app_operations_view hov
    JOIN balance_impacting_ops b ON hov.op_type_id = b.id
    JOIN LATERAL (
      SELECT account_name, amount
      FROM hive.get_impacted_balances(
        hov.body,
        CASE WHEN block_num >= __hardfork_one_block_num THEN TRUE ELSE FALSE END
      )
      WHERE asset_symbol_nai = 37
    ) bio ON TRUE
    WHERE hov.block_num BETWEEN _from AND _to
    ORDER BY hov.block_num, hov.id

  LOOP
    INSERT INTO hafbe_app.account_vests (account_id, vests)
    SELECT hav.id, __balance_change.vests
    FROM hive.btracker_app_accounts_view hav
    WHERE hav.name = __balance_change.account

    ON CONFLICT ON CONSTRAINT pk_account_vests_account DO 
    UPDATE SET vests = hafbe_app.account_vests.vests + EXCLUDED.vests;
  END LOOP;
END
$$
SET from_collapse_limit = 16
SET join_collapse_limit = 16
SET jit = OFF
;

CREATE OR REPLACE PROCEDURE hafbe_app.do_massive_processing(IN _appContext VARCHAR, IN _from INT, IN _to INT, IN _step INT, INOUT _last_block INT)
LANGUAGE 'plpgsql'
AS
$$
BEGIN
  RAISE NOTICE 'Entering massive processing of block range: <%, %>...', _from, _to;
  RAISE NOTICE 'Detaching HAF application context...';
  PERFORM hive.app_context_detach(_appContext);

  --- You can do here also other things to speedup your app, i.e. disable constrains, remove indexes etc.

  FOR b IN _from .. _to BY _step LOOP
    _last_block := b + _step - 1;

    IF _last_block > _to THEN --- in case the _step is larger than range length
      _last_block := _to;
    END IF;

    RAISE NOTICE 'Attempting to process a block range: <%, %>', b, _last_block;

    PERFORM hafbe_app.process_block_range_data_c(b, _last_block);

    COMMIT;

    RAISE NOTICE 'Block range: <%, %> processed successfully.', b, _last_block;

    EXIT WHEN NOT hafbe_app.continueProcessing();

  END LOOP;

  IF hafbe_app.continueProcessing() AND _last_block < _to THEN
    RAISE NOTICE 'Attempting to process a block range (rest): <%, %>', b, _last_block;
    --- Supplement last part of range if anything left.
    PERFORM hafbe_app.process_block_range_data_c(_last_block, _to);
    _last_block := _to;

    COMMIT;
    RAISE NOTICE 'Block range: <%, %> processed successfully.', b, _last_block;
  END IF;

  RAISE NOTICE 'Attaching HAF application context at block: %.', _last_block;
  PERFORM hive.app_context_attach(_appContext, _last_block);

 --- You should enable here all things previously disabled at begin of this function...

 RAISE NOTICE 'Leaving massive processing of block range: <%, %>...', _from, _to;
END
$$
;

CREATE OR REPLACE PROCEDURE hafbe_app.processBlock(_block INT)
LANGUAGE 'plpgsql'
AS
$$
BEGIN
  PERFORM hafbe_app.process_block_range_data_c(_block, _block);
  COMMIT; -- For single block processing we want to commit all changes for each one.
END
$$
;

/** Application entry point, which:
  - defines its data schema,
  - creates HAF application context,
  - starts application main-loop (which iterates infinitely). To stop it call `hafbe_app.stopProcessing();` from another session and commit its trasaction.
*/
CREATE OR REPLACE PROCEDURE hafbe_app.main(_appContext VARCHAR, _maxBlockLimit INT = NULL)
LANGUAGE 'plpgsql'
AS
$$
DECLARE
  __last_block INT;
  __next_block_range hive.blocks_range;
BEGIN
  IF NOT hive.app_context_exists(_appContext) THEN
    RAISE NOTICE 'Attempting to create a HAF application context...';
    PERFORM hive.app_create_context(_appContext);
    PERFORM hafbe_app.define_schema();
    COMMIT;
  END IF;

  PERFORM hafbe_app.allowProcessing();
  COMMIT;

  SELECT hafbe_app.lastProcessedBlock() INTO __last_block;

  RAISE NOTICE 'Last block processed by application: %', __last_block;

  IF NOT hive.app_context_is_attached(_appContext) THEN
    PERFORM hive.app_context_attach(_appContext, __last_block);
  END IF;

  RAISE NOTICE 'Entering application main loop...';

  IF _maxBlockLimit IS NULL THEN
    _maxBlockLimit = 2147483647;
  END IF;

  WHILE hafbe_app.continueProcessing() AND (_maxBlockLimit = 0 OR __last_block < _maxBlockLimit) LOOP
    __next_block_range := hive.app_next_block(_appContext);

    IF __next_block_range IS NULL THEN
      RAISE WARNING 'Waiting for next block...';
    ELSE
      IF _maxBlockLimit != 0 and __next_block_range.first_block > _maxBlockLimit THEN
        __next_block_range.first_block  := _maxBlockLimit;
      END IF;

      IF _maxBlockLimit != 0 and __next_block_range.last_block > _maxBlockLimit THEN
        __next_block_range.last_block  := _maxBlockLimit;
      END IF;

      RAISE NOTICE 'Attempting to process block range: <%,%>', __next_block_range.first_block, __next_block_range.last_block;

      IF __next_block_range.first_block != __next_block_range.last_block THEN
        CALL hafbe_app.do_massive_processing(_appContext, __next_block_range.first_block, __next_block_range.last_block, 100, __last_block);
      ELSE
        CALL hafbe_app.processBlock(__next_block_range.last_block);
        __last_block := __next_block_range.last_block;
      END IF;

    END IF;

  END LOOP;

  RAISE NOTICE 'Exiting application main loop at processed block: %.', __last_block;
  PERFORM hafbe_app.storeLastProcessedBlock(__last_block);

  COMMIT;
END
$$
;
