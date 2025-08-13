SET ROLE hafbe_owner;

CREATE OR REPLACE FUNCTION hafbe_backend.get_witness_voters_count(
    _witness_id INT,
    _filter_account_id INT
)
RETURNS INT -- noqa: LT01, CP05
LANGUAGE 'plpgsql' STABLE
AS
$$
BEGIN
  RETURN COUNT(*) 
  FROM hafbe_backend.current_witness_votes_view 
  WHERE 
    witness_id = _witness_id AND
    (_filter_account_id IS NULL OR voter_id = _filter_account_id);
END
$$;

CREATE OR REPLACE FUNCTION hafbe_backend.get_witness_votes_history_count(
    _witness_id INT,
    _filter_account_id INT,
    _block_range hive.blocks_range
)
RETURNS INT -- noqa: LT01, CP05
LANGUAGE 'plpgsql' STABLE
AS
$$
BEGIN
  RETURN COUNT(*) 
  FROM hafbe_backend.witness_votes_history_view 
  WHERE 
    witness_id = _witness_id AND
    (_block_range.first_block IS NULL OR source_op_block >= _block_range.first_block) AND
    (_block_range.last_block IS NULL OR source_op_block <= _block_range.last_block) AND
    (_filter_account_id IS NULL OR voter_id = _filter_account_id);
END
$$;

CREATE OR REPLACE FUNCTION hafbe_backend.get_witnesses_count()
RETURNS INT -- noqa: LT01, CP05
LANGUAGE 'plpgsql' STABLE
AS
$$
BEGIN
  RETURN COUNT(*)
  FROM hafbe_app.current_witnesses;
END
$$;

RESET ROLE;
