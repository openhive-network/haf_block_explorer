
/*
Żeby zrobić sync od początku:

TRUNCATE hive.katest_accountauth_a CASCADE

TRUNCATE hive.katest_keyauth_a CASCADE

TRUNCATE hive.katest_keyauth_b CASCADE

a potem ./process_test.sh --host=172.17.0.2 (steem11)

*/

CREATE OR REPLACE FUNCTION katest.main_test(
	_appcontext character varying,
	_from integer,
	_to integer,
	_step integer)
    RETURNS void
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE PARALLEL UNSAFE
AS $BODY$
DECLARE
_last_block INT ;
BEGIN

  FOR b IN _from .. _to BY _step LOOP
    _last_block := b + _step - 1;

    IF _last_block > _to THEN --- in case the _step is larger than range length
      _last_block := _to;
    END IF;

    RAISE NOTICE 'Attempting to process a block range: <%, %>', b, _last_block;

    PERFORM hive.app_state_providers_update(b, _last_block, _appContext);

    RAISE NOTICE 'Block range: <%, %> processed successfully.', b, _last_block;

  END LOOP;

 RAISE NOTICE 'Leaving massive processing of block range: <%, %>...', _from, _to;
END
$BODY$;

