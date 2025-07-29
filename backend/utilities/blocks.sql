SET ROLE hafbe_owner;

CREATE OR REPLACE FUNCTION hafbe_backend.get_haf_head_block()
RETURNS INT -- noqa: LT01, CP05
LANGUAGE 'plpgsql' STABLE
AS
$$
BEGIN
  RETURN bv.num FROM hive.blocks_view bv ORDER BY bv.num DESC LIMIT 1;
END
$$;

CREATE OR REPLACE FUNCTION hafbe_backend.get_hafbe_head_block()
RETURNS INT -- noqa: LT01, CP05
LANGUAGE 'plpgsql' STABLE
AS
$$
BEGIN
  RETURN current_block_num FROM hafd.contexts WHERE name = 'hafbe_app';
END
$$;

RESET ROLE;
