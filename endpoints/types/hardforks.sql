SET ROLE hafbe_owner;

/** openapi:components:schemas
hafbe_backend.hardfork:
  type: object
  properties:
    hardfork_num:
      type: integer
      description: Hardfork number. 0 is the genesis protocol, which no hardfork operation applies.
    block_num:
      type: integer
      description: Block that applied the hardfork; 1 for hardfork 0.
    timestamp:
      type: string
      format: date-time
      description: >-
        Production time (UTC) of that block. It can be later than the scheduled hardfork time
        that database_api.get_hardfork_properties reports.
 */
-- openapi-generated-code-begin
DROP TYPE IF EXISTS hafbe_backend.hardfork CASCADE;
CREATE TYPE hafbe_backend.hardfork AS (
    "hardfork_num" INT,
    "block_num" INT,
    "timestamp" TIMESTAMP
);
-- openapi-generated-code-end

/** openapi:components:schemas
hafbe_backend.array_of_hardforks:
  type: array
  items:
    $ref: '#/components/schemas/hafbe_backend.hardfork'
 */

RESET ROLE;
