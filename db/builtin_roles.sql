/**
 * Database Roles for HAF Block Explorer
 * ======================================
 *
 * This file defines the two database roles required by HAF Block Explorer:
 *
 * hafbe_owner
 * -----------
 * - Owner role with full read/write access to all HAF Block Explorer schemas
 * - Used by: Block processing scripts, schema migrations, admin operations
 * - Inherits from:
 *     - hive_applications_owner_group (HAF role for app owners)
 *     - reptracker_owner (Reputation Tracker ownership)
 *     - btracker_owner (Balance Tracker ownership)
 *     - hafah_owner (Account Authority History ownership) — granted conditionally
 * - Can create schemas, tables, functions, and process blocks
 * - Coordinates processing across all integrated submodule apps
 *
 * hafbe_user
 * ----------
 * - Read-only role for API access
 * - Used by: PostgREST (API server), read-only queries
 * - Inherits from:
 *     - hive_applications_group (HAF role for app users)
 *     - reptracker_user (Reputation Tracker read access)
 *     - btracker_user (Balance Tracker read access)
 *     - hafah_user (Account Authority History read access) — granted conditionally
 * - Has 10-second query timeout to prevent runaway queries
 * - Can only SELECT from tables, cannot modify data
 *
 * Role Hierarchy:
 * ---------------
 *   haf_admin
 *       └── hafbe_owner (schema owner, block processor)
 *               ├── reptracker_owner, btracker_owner, (hafah_owner if installed)
 *               └── hafbe_user (API read-only access)
 *                       └── reptracker_user, btracker_user, (hafah_user if installed)
 *
 * Security Model:
 * ---------------
 * - All hafbe schema objects are owned by hafbe_owner
 * - Submodule schemas are owned by their respective owner roles
 * - hafbe_user is granted SELECT on tables after installation
 * - PostgREST connects as hafbe_user for safe API access
 * - Block processing runs as hafbe_owner for write access
 *
 * Note: btracker_* and reptracker_* roles must be created before this script runs.
 * hafah_* roles are granted conditionally — hafah can be installed before or after hafbe.
 */

-- Create schema owner role (used for migrations and block processing)
-- Inherits from btracker and reptracker owner roles; hafah granted conditionally below
DO $$
BEGIN
  CREATE ROLE hafbe_owner WITH LOGIN INHERIT IN ROLE hive_applications_owner_group, reptracker_owner, btracker_owner;
EXCEPTION WHEN duplicate_object THEN RAISE NOTICE '%, skipping', SQLERRM USING ERRCODE = SQLSTATE;
END
$$;

-- Create API user role (read-only access via PostgREST)
-- Inherits from btracker and reptracker user roles; hafah granted conditionally below
DO $$
BEGIN
  CREATE ROLE hafbe_user WITH LOGIN INHERIT IN ROLE hive_applications_group, reptracker_user, btracker_user;
EXCEPTION WHEN duplicate_object THEN RAISE NOTICE '%, skipping', SQLERRM USING ERRCODE = SQLSTATE;
END
$$;

-- Grant hafah roles if available (hafah may be installed before or after hafbe)
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'hafah_owner') THEN
    GRANT hafah_owner TO hafbe_owner;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'hafah_user') THEN
    GRANT hafah_user TO hafbe_user;
  END IF;
END
$$;

-- Allow haf_admin to act as hafbe_owner (for installation scripts)
GRANT hafbe_owner TO haf_admin;

-- Allow hafbe_owner to act as hafbe_user (for testing)
GRANT hafbe_user TO hafbe_owner;

-- Limit API query execution time to prevent resource exhaustion
ALTER ROLE hafbe_user SET statement_timeout = '10s';
