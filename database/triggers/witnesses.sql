CREATE OR REPLACE FUNCTION hafbe_app.get_haf_acc_id(_account VARCHAR)
    RETURNS BIGINT
    LANGUAGE plpgsql
    AS $$
        DECLARE
            _id BIGINT;
        BEGIN
            SELECT id INTO _id FROM hive.accounts_view WHERE name = _account;
            RETURN _id;
        END;
    $$;

-- WITNESS PROPERTIES

CREATE OR REPLACE FUNCTION hafbe_app.witness_update( _block_num INTEGER, _timestamp TIMESTAMP, _trx_id BYTEA, _body JSONB )
    RETURNS VOID
    LANGUAGE plpgsql
    AS $$
        DECLARE
            _owner VARCHAR(16);
            _url TEXT;
            _signing_key TEXT;
            _max_block_size INTEGER;
            _hbd_interest_rate INTEGER;
            -- TODO: account creation fee
        BEGIN
            _owner := _body -> 'value' ->> 'owner';
            _url := _body -> 'value' ->> 'url';
            _signing_key := _body -> 'value' ->> 'block_signing_key';
            _max_block_size := _body -> 'value' ->> 'props' -> 'maximum_block_size';
            _hbd_interest_rate := _body -> 'value' ->> 'props' -> 'hbd_interest_rate';
            -- Update the current_witnesses table. 
            -- If the witness is not present, it will be added.

            INSERT INTO hafbe_app.current_witnesses (
                account, 
                url, 
                signing_key, 
                max_block_size, 
                hbd_interest_rate, 
                timestamp
            )
            VALUES (
                _owner, 
                _url, 
                _signing_key, 
                _max_block_size, 
                _hbd_interest_rate, 
                _timestamp
            )
            ON CONFLICT (account) 
            DO UPDATE 
            SET 
                url = _url, 
                signing_key = _signing_key, 
                max_block_size = _max_block_size, 
                hbd_interest_rate = _hbd_interest_rate, 
                timestamp = _timestamp;
        END;
    $$;



-- WITNESS VOTES

CREATE OR REPLACE FUNCTION hafbe_app.account_witness_vote( _block_num INTEGER, _timestamp TIMESTAMP, _trx_id BYTEA, _body JSONB )
    RETURNS VOID
    LANGUAGE plpgsql
    AS $$
        DECLARE
            _account INTEGER;
            _witness INTEGER;
            _approve BOOLEAN;
        BEGIN
            _account := _body -> 'value' ->> 'account';
            _witness := _body -> 'value' ->> 'witness';
            _approve := _body -> 'value' ->> 'approve';
            -- save historical entry
            INSERT INTO hafbe_app.witness_votes_history (account, witness, approve)
            VALUES (_account, _witness, _approve)
            ON CONFLICT (account, witness) DO UPDATE SET approve = _approve;
            -- update current witnesses
            IF _approve = true THEN
                INSERT INTO hafbe_app.current_witness_votes (account, witness, timestamp)
                VALUES (_account, _witness, _timestamp)
                ON CONFLICT (account, witness) DO NOTHING;
            ELSE
                DELETE FROM hafbe_app.current_witness_votes WHERE account = _account AND witness = _witness;
            END IF;
        END;
    $$;

CREATE OR REPLACE FUNCTION hafbe_app.account_witness_proxy( _block_num INTEGER, _timestamp TIMESTAMP, _trx_id BYTEA, _body JSONB )
    RETURNS VOID
    LANGUAGE plpgsql
    AS $$
        DECLARE
            _account INTEGER;
            _proxy INTEGER;
        BEGIN
            _account := _body -> 'value' ->> 'account';
            _proxy := _body -> 'value' ->> 'proxy';
            -- save historical entry
            INSERT INTO hafbe_app.account_proxies_history (account, proxy, timestamp)
            VALUES (_account, _proxy, _timestamp)
            -- update current witnesses proxy
            IF _proxy != '' THEN
                INSERT INTO hafbe_app.current_witness_proxy (account, proxy)
                VALUES (_account, _proxy)
                ON CONFLICT (account) DO UPDATE SET proxy = _proxy;
            END IF;
        END;
    $$;

-- if a proxy is cleared, we should not have a current_witness_proxy entry for that account
CREATE OR REPLACE FUNCTION hafbe_app.account_proxy_cleared( _block_num INTEGER, _timestamp TIMESTAMP, _trx_id BYTEA, _body JSONB )
    RETURNS VOID
    LANGUAGE plpgsql
    AS $$
        DECLARE
            _account INTEGER;
        BEGIN
            _account := _body -> 'value' ->> 'account';
            -- update current witnesses proxy
            DELETE FROM hafbe_app.current_witness_proxy WHERE account = _account;
        END;
    $$;
