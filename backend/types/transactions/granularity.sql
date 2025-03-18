SET ROLE hafbe_owner;

/** openapi:components:schemas
hafbe_types.granularity:
  type: string
  enum:
    - daily
    - monthly
    - yearly
 */
-- openapi-generated-code-begin
DROP TYPE IF EXISTS hafbe_types.granularity CASCADE;
CREATE TYPE hafbe_types.granularity AS ENUM (
    'daily',
    'monthly',
    'yearly'
);
-- openapi-generated-code-end

RESET ROLE;
