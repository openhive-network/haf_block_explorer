SET ROLE hafbe_owner;

/** openapi
openapi: 3.1.0
info:
  title: HAF Block Explorer
  description: >-
    HAF block explorer is an API for getting information about
    transactions/operations included in Hive blocks, as well as block producer (witness)
    information.
  license:
    name: MIT License
    url: https://opensource.org/license/mit

externalDocs:
  description: HAF Block Explorer gitlab repository
  url: https://gitlab.syncad.com/hive/haf_block_explorer
tags:
  - name: Block-numbers
    description: Information about blocks
  - name: Accounts
    description: Information about accounts
  - name: Witnesses
    description: Information about witnesses
  - name: Other
    description: General API information
servers:
  - url: /hafbe-api
 */

CREATE SCHEMA IF NOT EXISTS hafbe_endpoints AUTHORIZATION hafbe_owner;

DO $__$
DECLARE 
  swagger_url TEXT;
BEGIN
  swagger_url := current_setting('custom.swagger_url')::TEXT;
  
EXECUTE FORMAT(
'create or replace function hafbe_endpoints.root() returns json as $_$
declare
-- openapi-spec
-- openapi-generated-code-begin
-- openapi-generated-code-end
begin
  return openapi;
end
$_$ language plpgsql;'
, swagger_url);

END
$__$;

RESET ROLE;
