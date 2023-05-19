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
            _max_block_size := _body -> 'value' -> 'props' ->> 'maximum_block_size';
            --_hbd_interest_rate := _body -> 'value' -> 'props' ->> 'hbd_interest_rate';
            -- Update the current_witnesses table. 
            -- If the witness is not present, it will be added.

            INSERT INTO hafbe_app.current_witnesses (
                witness_id, 
                url, 
                signing_key, 
                block_size
            )
            VALUES (
                hafbe_app.get_haf_acc_id(_owner), 
                _url, 
                _signing_key, 
                _max_block_size
            )
            ON CONFLICT (witness_id) 
            DO UPDATE 
            SET 
                url = _url, 
                signing_key = _signing_key, 
                block_size = _max_block_size;
        END;
    $$;



-- WITNESS VOTES

CREATE OR REPLACE FUNCTION hafbe_app.account_witness_vote( _block_num INTEGER, _timestamp TIMESTAMP, _trx_id BYTEA, _body JSONB )
    RETURNS VOID
    LANGUAGE plpgsql
    AS $$
        DECLARE
            _account_id INT;
            _witness_id INT;
            _approve BOOLEAN;
        BEGIN
            _account_id := hafbe_app.get_haf_acc_id(_body -> 'value' ->> 'account');
            _witness_id := hafbe_app.get_haf_acc_id(_body -> 'value' ->> 'witness');
            _approve := _body -> 'value' ->> 'approve';
            -- save historical entry
            INSERT INTO hafbe_app.witness_votes_history (voter_id, witness_id, approve, timestamp)
            VALUES (_account_id, _witness_id, _approve, _timestamp);
            -- update current witnesses
            IF _approve = true THEN
                INSERT INTO hafbe_app.current_witness_votes (voter_id, witness_id, timestamp)
                VALUES (_account_id, _witness_id, _timestamp)
                ON CONFLICT (voter_id, witness_id) DO NOTHING;
            ELSE
                DELETE FROM hafbe_app.current_witness_votes WHERE voter_id = _account_id AND witness_id = _witness_id;
            END IF;
        END;
    $$;

CREATE OR REPLACE FUNCTION hafbe_app.account_witness_proxy( _block_num INTEGER, _timestamp TIMESTAMP, _trx_id BYTEA, _body JSONB )
    RETURNS VOID
    LANGUAGE plpgsql
    AS $$
        DECLARE
            _account_id INT;
            _proxy_id INT;
        BEGIN
            _account_id := hafbe_app.get_haf_acc_id(_body -> 'value' ->> 'account');
            _proxy_id := hafbe_app.get_haf_acc_id(_body -> 'value' ->> 'proxy');
            IF _proxy_id IS NOT NULL AND _account_id IS NOT NULL THEN
                -- save historical entry
                INSERT INTO hafbe_app.account_proxies_history (account_id, proxy_id, timestamp)
                VALUES (_account_id, _proxy_id, _timestamp);
                -- update current witnesses proxy
                INSERT INTO hafbe_app.current_account_proxies (account_id, proxy_id)
                VALUES (_account_id, _proxy_id)
                ON CONFLICT (account_id) DO UPDATE SET proxy_id = _proxy_id;
            END IF;
        END;
    $$;

-- if a proxy is cleared, we should not have a current_witness_proxy entry for that account
CREATE OR REPLACE FUNCTION hafbe_app.account_proxy_cleared( _block_num INTEGER, _timestamp TIMESTAMP, _trx_id BYTEA, _body JSONB )
    RETURNS VOID
    LANGUAGE plpgsql
    AS $$
        DECLARE
            _account_id INT;
        BEGIN
            _account_id := hafbe_app.get_haf_acc_id(_body -> 'value' ->> 'account');
            -- update current witnesses proxy
            DELETE FROM hafbe_app.current_account_proxies WHERE account_id = _account_id;
        END;
    $$;
