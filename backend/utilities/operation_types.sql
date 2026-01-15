SET ROLE hafbe_owner;

-- ============================================================================
-- Convenience functions for commonly used operation types
-- These provide semantic names and avoid magic numbers scattered throughout the code
-- Each function returns the operation type ID by looking up the name in hafd.operation_types
-- ============================================================================

-- ============================================================================
-- Comment-related operations
-- ============================================================================

CREATE OR REPLACE FUNCTION hafbe_backend.op_vote()
RETURNS INT LANGUAGE plpgsql STABLE AS $$
BEGIN
  RETURN (SELECT id FROM hafd.operation_types WHERE name = 'hive::protocol::vote_operation');
END;
$$;

CREATE OR REPLACE FUNCTION hafbe_backend.op_comment()
RETURNS INT LANGUAGE plpgsql STABLE AS $$
BEGIN
  RETURN (SELECT id FROM hafd.operation_types WHERE name = 'hive::protocol::comment_operation');
END;
$$;

CREATE OR REPLACE FUNCTION hafbe_backend.op_delete_comment()
RETURNS INT LANGUAGE plpgsql STABLE AS $$
BEGIN
  RETURN (SELECT id FROM hafd.operation_types WHERE name = 'hive::protocol::delete_comment_operation');
END;
$$;

CREATE OR REPLACE FUNCTION hafbe_backend.op_comment_options()
RETURNS INT LANGUAGE plpgsql STABLE AS $$
BEGIN
  RETURN (SELECT id FROM hafd.operation_types WHERE name = 'hive::protocol::comment_options_operation');
END;
$$;

CREATE OR REPLACE FUNCTION hafbe_backend.op_author_reward()
RETURNS INT LANGUAGE plpgsql STABLE AS $$
BEGIN
  RETURN (SELECT id FROM hafd.operation_types WHERE name = 'hive::protocol::author_reward_operation');
END;
$$;

CREATE OR REPLACE FUNCTION hafbe_backend.op_curation_reward()
RETURNS INT LANGUAGE plpgsql STABLE AS $$
BEGIN
  RETURN (SELECT id FROM hafd.operation_types WHERE name = 'hive::protocol::curation_reward_operation');
END;
$$;

CREATE OR REPLACE FUNCTION hafbe_backend.op_comment_reward()
RETURNS INT LANGUAGE plpgsql STABLE AS $$
BEGIN
  RETURN (SELECT id FROM hafd.operation_types WHERE name = 'hive::protocol::comment_reward_operation');
END;
$$;

CREATE OR REPLACE FUNCTION hafbe_backend.op_comment_payout_update()
RETURNS INT LANGUAGE plpgsql STABLE AS $$
BEGIN
  RETURN (SELECT id FROM hafd.operation_types WHERE name = 'hive::protocol::comment_payout_update_operation');
END;
$$;

CREATE OR REPLACE FUNCTION hafbe_backend.op_comment_benefactor_reward()
RETURNS INT LANGUAGE plpgsql STABLE AS $$
BEGIN
  RETURN (SELECT id FROM hafd.operation_types WHERE name = 'hive::protocol::comment_benefactor_reward_operation');
END;
$$;

CREATE OR REPLACE FUNCTION hafbe_backend.op_effective_comment_vote()
RETURNS INT LANGUAGE plpgsql STABLE AS $$
BEGIN
  RETURN (SELECT id FROM hafd.operation_types WHERE name = 'hive::protocol::effective_comment_vote_operation');
END;
$$;

CREATE OR REPLACE FUNCTION hafbe_backend.op_ineffective_delete_comment()
RETURNS INT LANGUAGE plpgsql STABLE AS $$
BEGIN
  RETURN (SELECT id FROM hafd.operation_types WHERE name = 'hive::protocol::ineffective_delete_comment_operation');
END;
$$;

-- ============================================================================
-- Witness operations
-- ============================================================================

CREATE OR REPLACE FUNCTION hafbe_backend.op_account_witness_vote()
RETURNS INT LANGUAGE plpgsql STABLE AS $$
BEGIN
  RETURN (SELECT id FROM hafd.operation_types WHERE name = 'hive::protocol::account_witness_vote_operation');
END;
$$;

CREATE OR REPLACE FUNCTION hafbe_backend.op_account_witness_proxy()
RETURNS INT LANGUAGE plpgsql STABLE AS $$
BEGIN
  RETURN (SELECT id FROM hafd.operation_types WHERE name = 'hive::protocol::account_witness_proxy_operation');
END;
$$;

CREATE OR REPLACE FUNCTION hafbe_backend.op_proxy_cleared()
RETURNS INT LANGUAGE plpgsql STABLE AS $$
BEGIN
  RETURN (SELECT id FROM hafd.operation_types WHERE name = 'hive::protocol::proxy_cleared_operation');
END;
$$;

CREATE OR REPLACE FUNCTION hafbe_backend.op_producer_reward()
RETURNS INT LANGUAGE plpgsql STABLE AS $$
BEGIN
  RETURN (SELECT id FROM hafd.operation_types WHERE name = 'hive::protocol::producer_reward_operation');
END;
$$;

CREATE OR REPLACE FUNCTION hafbe_backend.op_producer_missed()
RETURNS INT LANGUAGE plpgsql STABLE AS $$
BEGIN
  RETURN (SELECT id FROM hafd.operation_types WHERE name = 'hive::protocol::producer_missed_operation');
END;
$$;

CREATE OR REPLACE FUNCTION hafbe_backend.op_witness_update()
RETURNS INT LANGUAGE plpgsql STABLE AS $$
BEGIN
  RETURN (SELECT id FROM hafd.operation_types WHERE name = 'hive::protocol::witness_update_operation');
END;
$$;

CREATE OR REPLACE FUNCTION hafbe_backend.op_witness_set_properties()
RETURNS INT LANGUAGE plpgsql STABLE AS $$
BEGIN
  RETURN (SELECT id FROM hafd.operation_types WHERE name = 'hive::protocol::witness_set_properties_operation');
END;
$$;

CREATE OR REPLACE FUNCTION hafbe_backend.op_feed_publish()
RETURNS INT LANGUAGE plpgsql STABLE AS $$
BEGIN
  RETURN (SELECT id FROM hafd.operation_types WHERE name = 'hive::protocol::feed_publish_operation');
END;
$$;

-- ============================================================================
-- Account creation operations
-- ============================================================================

CREATE OR REPLACE FUNCTION hafbe_backend.op_account_create()
RETURNS INT LANGUAGE plpgsql STABLE AS $$
BEGIN
  RETURN (SELECT id FROM hafd.operation_types WHERE name = 'hive::protocol::account_create_operation');
END;
$$;

CREATE OR REPLACE FUNCTION hafbe_backend.op_create_claimed_account()
RETURNS INT LANGUAGE plpgsql STABLE AS $$
BEGIN
  RETURN (SELECT id FROM hafd.operation_types WHERE name = 'hive::protocol::create_claimed_account_operation');
END;
$$;

CREATE OR REPLACE FUNCTION hafbe_backend.op_account_create_with_delegation()
RETURNS INT LANGUAGE plpgsql STABLE AS $$
BEGIN
  RETURN (SELECT id FROM hafd.operation_types WHERE name = 'hive::protocol::account_create_with_delegation_operation');
END;
$$;

CREATE OR REPLACE FUNCTION hafbe_backend.op_account_created()
RETURNS INT LANGUAGE plpgsql STABLE AS $$
BEGIN
  RETURN (SELECT id FROM hafd.operation_types WHERE name = 'hive::protocol::account_created_operation');
END;
$$;

CREATE OR REPLACE FUNCTION hafbe_backend.op_claim_account()
RETURNS INT LANGUAGE plpgsql STABLE AS $$
BEGIN
  RETURN (SELECT id FROM hafd.operation_types WHERE name = 'hive::protocol::claim_account_operation');
END;
$$;

-- ============================================================================
-- Account recovery operations
-- ============================================================================

CREATE OR REPLACE FUNCTION hafbe_backend.op_recover_account()
RETURNS INT LANGUAGE plpgsql STABLE AS $$
BEGIN
  RETURN (SELECT id FROM hafd.operation_types WHERE name = 'hive::protocol::recover_account_operation');
END;
$$;

CREATE OR REPLACE FUNCTION hafbe_backend.op_changed_recovery_account()
RETURNS INT LANGUAGE plpgsql STABLE AS $$
BEGIN
  RETURN (SELECT id FROM hafd.operation_types WHERE name = 'hive::protocol::changed_recovery_account_operation');
END;
$$;

CREATE OR REPLACE FUNCTION hafbe_backend.op_expired_account_notification()
RETURNS INT LANGUAGE plpgsql STABLE AS $$
BEGIN
  RETURN (SELECT id FROM hafd.operation_types WHERE name = 'hive::protocol::expired_account_notification_operation');
END;
$$;

CREATE OR REPLACE FUNCTION hafbe_backend.op_decline_voting_rights()
RETURNS INT LANGUAGE plpgsql STABLE AS $$
BEGIN
  RETURN (SELECT id FROM hafd.operation_types WHERE name = 'hive::protocol::decline_voting_rights_operation');
END;
$$;

CREATE OR REPLACE FUNCTION hafbe_backend.op_declined_voting_rights()
RETURNS INT LANGUAGE plpgsql STABLE AS $$
BEGIN
  RETURN (SELECT id FROM hafd.operation_types WHERE name = 'hive::protocol::declined_voting_rights_operation');
END;
$$;

-- ============================================================================
-- Proof of work (mining) operations
-- ============================================================================

CREATE OR REPLACE FUNCTION hafbe_backend.op_pow()
RETURNS INT LANGUAGE plpgsql STABLE AS $$
BEGIN
  RETURN (SELECT id FROM hafd.operation_types WHERE name = 'hive::protocol::pow_operation');
END;
$$;

CREATE OR REPLACE FUNCTION hafbe_backend.op_pow2()
RETURNS INT LANGUAGE plpgsql STABLE AS $$
BEGIN
  RETURN (SELECT id FROM hafd.operation_types WHERE name = 'hive::protocol::pow2_operation');
END;
$$;

-- ============================================================================
-- Helper functions: Operation type arrays for processing functions
-- ============================================================================

CREATE OR REPLACE FUNCTION hafbe_backend.get_comment_history_allowed_op_types()
RETURNS INT[] -- noqa: LT01, CP05
LANGUAGE 'plpgsql' STABLE
AS
$$
BEGIN
  RETURN ARRAY[
    hafbe_backend.op_vote(),                       -- 0: vote_operation
    hafbe_backend.op_comment(),                    -- 1: comment_operation
    hafbe_backend.op_delete_comment(),             -- 17: delete_comment_operation
    hafbe_backend.op_comment_options(),            -- 19: comment_options_operation
    hafbe_backend.op_author_reward(),              -- 51: author_reward_operation
    hafbe_backend.op_curation_reward(),            -- 52: curation_reward_operation
    hafbe_backend.op_comment_reward(),             -- 53: comment_reward_operation
    hafbe_backend.op_comment_payout_update(),      -- 61: comment_payout_update_operation
    hafbe_backend.op_comment_benefactor_reward(),  -- 63: comment_benefactor_reward_operation
    hafbe_backend.op_effective_comment_vote(),     -- 72: effective_comment_vote_operation
    hafbe_backend.op_ineffective_delete_comment()  -- 73: ineffective_delete_comment_operation
  ];
END
$$;

CREATE OR REPLACE FUNCTION hafbe_backend.get_comment_history_operation_types(
    _operations TEXT
)
RETURNS INT []-- noqa: LT01, CP05
LANGUAGE 'plpgsql' STABLE
SET JIT = OFF
AS
$$
DECLARE
  _allowed_ids   INT[] := hafbe_backend.get_comment_history_allowed_op_types();
  _operation_ids INT[] := (SELECT string_to_array(_operations, ',')::INT[]);
BEGIN
  IF _operations IS NULL THEN
    RETURN _allowed_ids;
  END IF;

  PERFORM hafah_backend.validate_operation_types(_operation_ids, _allowed_ids);

  RETURN _operation_ids;
END
$$;

RESET ROLE;
