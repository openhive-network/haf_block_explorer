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

-- ============================================================================
-- Statistics defaults
-- ============================================================================

CREATE OR REPLACE FUNCTION hafbe_backend.default_stats_window()
RETURNS INTERVAL LANGUAGE plpgsql IMMUTABLE AS $$
BEGIN
  -- Range a statistics endpoint falls back to when the caller supplies no lower bound.
  -- Only applied where an unbounded series would be unreasonably large (currently the
  -- daily operation-type histogram: ~3.7k periods / ~6.6 MB over full history). Mirrors
  -- the 1-year default of the network statistics endpoints. An explicit from-block always wins.
  RETURN INTERVAL '1 year';
END;
$$;

-- ============================================================================
-- Account Parameters Defaults
-- These provide single source of truth for account_parameters table defaults
-- ============================================================================

CREATE OR REPLACE FUNCTION hafbe_backend.default_can_vote()
RETURNS BOOLEAN LANGUAGE plpgsql IMMUTABLE AS $$
BEGIN
  RETURN TRUE;  -- Accounts can vote by default
END;
$$;

CREATE OR REPLACE FUNCTION hafbe_backend.default_mined()
RETURNS BOOLEAN LANGUAGE plpgsql IMMUTABLE AS $$
BEGIN
  RETURN TRUE;  -- Default assumption for legacy accounts
END;
$$;

CREATE OR REPLACE FUNCTION hafbe_backend.default_recovery_account()
RETURNS TEXT LANGUAGE plpgsql IMMUTABLE AS $$
BEGIN
  RETURN '';  -- Empty string means no recovery account set
END;
$$;

CREATE OR REPLACE FUNCTION hafbe_backend.default_timestamp()
RETURNS TIMESTAMP LANGUAGE plpgsql IMMUTABLE AS $$
BEGIN
  RETURN '1970-01-01T00:00:00'::TIMESTAMP;  -- Unix epoch as placeholder
END;
$$;

CREATE OR REPLACE FUNCTION hafbe_backend.default_pending_claimed_accounts()
RETURNS INT LANGUAGE plpgsql IMMUTABLE AS $$
BEGIN
  RETURN 0;  -- No pending claimed accounts by default
END;
$$;

-- ============================================================================
-- Blockchain-specific Account Names
-- Special account names with semantic meaning in the Hive protocol
-- ============================================================================

CREATE OR REPLACE FUNCTION hafbe_backend.pre_hf11_recovery_account()
RETURNS TEXT LANGUAGE plpgsql IMMUTABLE AS $$
BEGIN
  RETURN 'steem';  -- Before HF11, all accounts defaulted to 'steem' as recovery
END;
$$;

CREATE OR REPLACE FUNCTION hafbe_backend.temp_creator_account()
RETURNS TEXT LANGUAGE plpgsql IMMUTABLE AS $$
BEGIN
  RETURN 'temp';  -- Special creator name indicating self-created account
END;
$$;

RESET ROLE;
