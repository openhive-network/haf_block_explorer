SET ROLE hafbe_owner;

/** openapi:components:schemas
hafbe_types.proxy_power:
  type: object
  properties:
    account:
      type: string
    proxy_date:
      type: string
      format: date-time
    proxied_vests:
      type: number
      format: double
      description: Own vesting shares plus sum of proxied vesting shares (levels 1–4)
*/
-- openapi-generated-code-begin
DROP TYPE IF EXISTS hafbe_types.proxy_power CASCADE;
CREATE TYPE hafbe_types.proxy_power AS (
    "account" TEXT,
    "proxy_date" TIMESTAMP,
    "proxied_vests" FLOAT
);
-- openapi-generated-code-end

RESET ROLE;
