-- Every function in hafbe_endpoints, the schema PostgREST exposes, is STABLE or
-- IMMUTABLE, so PostgREST runs it in a READ ONLY transaction whether it is
-- called by GET or by POST (a rewriter forwarding GETs as POSTs would otherwise
-- run a VOLATILE one READ WRITE). Then the endpoints whose volatility was once
-- missing are called as PostgREST's role, hafbe_user, inside a READ ONLY
-- transaction.
-- Runs as haf_shared_consumer in the run's clone (.aidev/run-checks.sh
-- app_install) and writes nothing.
\set ON_ERROR_STOP on

DO $$
DECLARE
  _volatile TEXT;
BEGIN
  SELECT string_agg(p.oid::regprocedure::TEXT, ', ' ORDER BY p.proname)
  INTO _volatile
  FROM pg_proc p
  WHERE p.pronamespace = 'hafbe_endpoints'::regnamespace
    AND p.provolatile = 'v';

  IF _volatile IS NOT NULL THEN
    RAISE EXCEPTION 'hafbe_endpoints functions declared VOLATILE: %', _volatile;
  END IF;

  RAISE NOTICE 'every function in hafbe_endpoints is STABLE or IMMUTABLE';
END
$$;

BEGIN READ ONLY;

SET LOCAL ROLE hafbe_owner;
SET LOCAL ROLE hafbe_user;

DO $$
BEGIN
  IF current_setting('transaction_read_only') <> 'on' THEN
    RAISE EXCEPTION 'the endpoint calls are not running in a READ ONLY transaction';
  END IF;

  PERFORM hafbe_endpoints.root();
  PERFORM hafbe_endpoints.get_total_wallet_addresses();

  RAISE NOTICE 'the endpoints run as hafbe_user in a READ ONLY transaction';
END
$$;

ROLLBACK;
