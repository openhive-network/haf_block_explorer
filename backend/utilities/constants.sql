SET ROLE hafbe_owner;

-- ============================================================================
-- Constants for HAF Block Explorer
-- These provide semantic names for magic numbers used throughout the codebase
-- ============================================================================

-- ============================================================================
-- Numeric Asset Identifiers (NAI)
-- Use btracker's NAI functions - they are the single source of truth:
--   btracker_backend.nai_hbd()
--   btracker_backend.nai_hive()
--   btracker_backend.nai_vests()
--   btracker_backend.nai_vests_as_hive()
-- ============================================================================

-- ============================================================================
-- Blockchain constants
-- ============================================================================

CREATE OR REPLACE FUNCTION hafbe_backend.genesis_block_num()
RETURNS INT LANGUAGE plpgsql IMMUTABLE AS $$
BEGIN
  RETURN 1;  -- The first block in the blockchain
END;
$$;

-- ============================================================================
-- Pagination defaults
-- ============================================================================

CREATE OR REPLACE FUNCTION hafbe_backend.default_max_page_count()
RETURNS INT LANGUAGE plpgsql IMMUTABLE AS $$
BEGIN
  RETURN 10;  -- Maximum number of pages to fetch in a single query
END;
$$;

CREATE OR REPLACE FUNCTION hafbe_backend.default_max_page_size()
RETURNS INT LANGUAGE plpgsql IMMUTABLE AS $$
BEGIN
  RETURN 1000;  -- Maximum page size for pagination
END;
$$;

RESET ROLE;
