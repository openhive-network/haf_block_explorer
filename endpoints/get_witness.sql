SET ROLE hafbe_owner;

DROP FUNCTION IF EXISTS hafbe_endpoints.get_witness_voters_num(account TEXT);
CREATE OR REPLACE FUNCTION hafbe_endpoints.get_witness_voters_num(account TEXT)
RETURNS INT
LANGUAGE 'plpgsql' STABLE
AS
$$
DECLARE
  _witness_id INT = hafbe_backend.get_account_id(account);
BEGIN
  PERFORM set_config('response.headers', '[{"Cache-Control": "public, max-age=2"}]', true);
  RETURN COUNT(1) FROM hafbe_app.current_witness_votes WHERE witness_id = _witness_id;
END
$$;

-- Witness page endpoint
DROP FUNCTION IF EXISTS hafbe_endpoints.get_witness_voters(
    account TEXT,
    sort hafbe_types.order_by_votes, -- noqa: LT01, CP05
    direction hafbe_types.order_is, -- noqa: LT01, CP05
    "limit" INT
);
CREATE OR REPLACE FUNCTION hafbe_endpoints.get_witness_voters(
    account TEXT,
    sort hafbe_types.order_by_votes = 'vests', -- noqa: LT01, CP05
    direction hafbe_types.order_is = 'desc', -- noqa: LT01, CP05
    "limit" INT = 2147483647
)
RETURNS SETOF hafbe_types.witness_voters -- noqa: LT01, CP05
LANGUAGE 'plpgsql'
STABLE
SET from_collapse_limit = 16
SET join_collapse_limit = 16
SET jit = OFF
AS
$$
DECLARE
_witness_id INT = hafbe_backend.get_account_id(account);
BEGIN

PERFORM set_config('response.headers', '[{"Cache-Control": "public, max-age=2"}]', true);

RETURN QUERY EXECUTE format(
  $query$

  WITH limited_set AS (
    SELECT 
      (SELECT av.name FROM hive.accounts_view av WHERE av.id = wvsc.voter_id)::TEXT AS voter,
      wvsc.voter_id, wvsc.vests, wvsc.account_vests, wvsc.proxied_vests, wvsc.timestamp
    FROM hafbe_app.witness_voters_stats_cache wvsc
    WHERE witness_id = %L   
  ),
  limited_set_order AS MATERIALIZED (
    SELECT * FROM limited_set
    ORDER BY
      (CASE WHEN %L = 'desc' THEN %I ELSE NULL END) DESC,
      (CASE WHEN %L = 'asc' THEN %I ELSE NULL END) ASC  
    LIMIT %L
  ),
  get_block_num AS MATERIALIZED
  (SELECT bv.num AS block_num FROM hive.blocks_view bv ORDER BY bv.num DESC LIMIT 1)

  SELECT ls.voter, 
  ls.vests,
  (SELECT hive.get_vesting_balance((SELECT gbn.block_num FROM get_block_num gbn), ls.vests))::BIGINT,
  ls.account_vests,
  (SELECT hive.get_vesting_balance((SELECT gbn.block_num FROM get_block_num gbn), ls.account_vests))::BIGINT,
  ls.proxied_vests,
  (SELECT hive.get_vesting_balance((SELECT gbn.block_num FROM get_block_num gbn), ls.proxied_vests))::BIGINT,
  ls.timestamp
  FROM limited_set_order ls
  ORDER BY
    (CASE WHEN %L = 'desc' THEN %I ELSE NULL END) DESC,
    (CASE WHEN %L = 'asc' THEN %I ELSE NULL END) ASC
  ;

  $query$,
  _witness_id, direction, sort, direction, sort, "limit",
  direction, sort, direction, sort
) res;

END
$$;

-- Witness page endpoint
DROP FUNCTION IF EXISTS hafbe_endpoints.get_witness_votes_history(
    account TEXT,
    sort hafbe_types.order_by_votes,
    direction hafbe_types.order_is,
    "limit" INT,
    from_time TIMESTAMP,
    to_time TIMESTAMP
);
CREATE OR REPLACE FUNCTION hafbe_endpoints.get_witness_votes_history(
    account TEXT,
    sort hafbe_types.order_by_votes = 'timestamp', -- noqa: LT01, CP05
    direction hafbe_types.order_is = 'desc', -- noqa: LT01, CP05
    "limit" INT = 100,
    from_time TIMESTAMP = '1970-01-01T00:00:00'::TIMESTAMP,
    to_time TIMESTAMP = NOW()
)
RETURNS SETOF hafbe_types.witness_votes_history -- noqa: LT01, CP05
LANGUAGE 'plpgsql'
STABLE
SET from_collapse_limit = 16
SET join_collapse_limit = 16
SET jit = OFF
AS
$$
DECLARE
_witness_id INT = hafbe_backend.get_account_id(account);
BEGIN

PERFORM set_config('response.headers', '[{"Cache-Control": "public, max-age=2"}]', true);

RETURN QUERY EXECUTE format(
  $query$

  WITH select_range AS MATERIALIZED (
    SELECT 
      (SELECT av.name FROM hive.accounts_view av WHERE av.id = wvh.voter_id)::TEXT AS voter,
      * 
    FROM hafbe_app.witness_votes_history_cache wvh
    WHERE wvh.witness_id = %L
    AND wvh.timestamp BETWEEN  %L AND  %L
    ORDER BY wvh.timestamp DESC
    LIMIT %L
  ),
  get_block_num AS MATERIALIZED
    (SELECT bv.num AS block_num FROM hive.blocks_view bv ORDER BY bv.num DESC LIMIT 1),
  select_votes_history AS (
  SELECT
    wvh.voter, wvh.approve, 
    (wvh.account_vests + wvh.proxied_vests ) AS vests, 
    (SELECT hive.get_vesting_balance((SELECT gbn.block_num FROM get_block_num gbn), (wvh.account_vests + wvh.proxied_vests) ))::BIGINT AS vests_hive_power,
    wvh.account_vests AS account_vests, 
    (SELECT hive.get_vesting_balance((SELECT gbn.block_num FROM get_block_num gbn), wvh.account_vests))::BIGINT AS account_hive_power,
    wvh.proxied_vests AS proxied_vests,
    (SELECT hive.get_vesting_balance((SELECT gbn.block_num FROM get_block_num gbn), wvh.proxied_vests))::BIGINT AS proxied_hive_power,
    wvh.timestamp AS timestamp
  FROM select_range wvh
  )
  SELECT * FROM select_votes_history
  ORDER BY
    (CASE WHEN %L = 'desc' THEN  %I ELSE NULL END) DESC,
    (CASE WHEN %L = 'asc' THEN %I ELSE NULL END) ASC
  ;
  $query$,
  _witness_id,from_time, to_time, "limit", direction, sort, direction, sort
) res;
END
$$;

-- Witness page endpoint
DROP FUNCTION IF EXISTS hafbe_endpoints.get_witnesses(
    "limit" INT,
    "offset" INT,
    sort hafbe_types.order_by_witness,
    direction hafbe_types.order_is
);
CREATE OR REPLACE FUNCTION hafbe_endpoints.get_witnesses(
    "limit" INT = 100,
    "offset" INT = 0,
    sort hafbe_types.order_by_witness = 'votes', -- noqa: LT01, CP05
    direction hafbe_types.order_is = 'desc' -- noqa: LT01, CP05
)
RETURNS SETOF hafbe_types.witness_setof -- noqa: LT01, CP05
LANGUAGE 'plpgsql'
STABLE
SET from_collapse_limit = 16
SET join_collapse_limit = 16
SET jit = OFF
AS
$$
BEGIN

PERFORM set_config('response.headers', '[{"Cache-Control": "public, max-age=2"}]', true);

RETURN QUERY EXECUTE format(
  $query$

  WITH limited_set AS (
    SELECT
      cw.witness_id, 
      (SELECT av.name FROM hive.accounts_view av WHERE av.id = cw.witness_id)::TEXT AS witness,
      cw.url,
      cw.price_feed,
      cw.bias,
      (NOW() - cw.feed_updated_at)::INTERVAL AS feed_age,
      cw.block_size, 
      cw.signing_key, 
      cw.version, 
      b.rank, 
      COALESCE(b.votes,0) AS votes, 
      COALESCE(b.voters_num,0) AS voters_num, 
      COALESCE(c.votes_daily_change, 0) AS votes_daily_change, 
      COALESCE(c.voters_num_daily_change,0) AS voters_num_daily_change,
      COALESCE(
      (
        SELECT count(*) as missed
        FROM hive.account_operations_view aov
        WHERE aov.op_type_id = 86 AND aov.account_id = cw.witness_id
      )::INT
      ,0) AS missed_blocks,
      COALESCE(cw.hbd_interest_rate,0) AS hbd_interest_rate
    FROM hafbe_app.current_witnesses cw
    LEFT JOIN hafbe_app.witness_votes_cache b ON b.witness_id = cw.witness_id
    LEFT JOIN hafbe_app.witness_votes_change_cache c ON c.witness_id = cw.witness_id
  ),
  limited_set_order AS MATERIALIZED (
    SELECT * FROM limited_set
    ORDER BY
      (CASE WHEN %L = 'desc' THEN %I ELSE NULL END) DESC,
      (CASE WHEN %L = 'asc' THEN %I ELSE NULL END) ASC
    OFFSET %L
    LIMIT %L
  ),
get_block_num AS MATERIALIZED
(SELECT bv.num AS block_num FROM hive.blocks_view bv ORDER BY bv.num DESC LIMIT 1)

  SELECT
    ls.witness, 
    ls.rank, 
    ls.url,
    ls.votes,
    (SELECT hive.get_vesting_balance((SELECT gbn.block_num FROM get_block_num gbn), ls.votes))::BIGINT, 
    ls.votes_daily_change,
    (SELECT hive.get_vesting_balance((SELECT gbn.block_num FROM get_block_num gbn), ls.votes_daily_change))::BIGINT, 
    ls.voters_num,
    ls.voters_num_daily_change,
    ls.price_feed, 
    ls.bias, 
    ls.feed_age, 
    ls.block_size, 
    ls.signing_key, 
    ls.version,
    ls.missed_blocks,
    ls.hbd_interest_rate
  FROM limited_set_order ls
  ORDER BY
    (CASE WHEN %L = 'desc' THEN %I ELSE NULL END) DESC,
    (CASE WHEN %L = 'asc' THEN %I ELSE NULL END) ASC

  $query$,
  direction,sort, direction,sort, "offset","limit",
  direction, sort, direction,sort
)
;

END
$$;

-- Witness page endpoint
DROP FUNCTION IF EXISTS hafbe_endpoints.get_witness(account TEXT);
CREATE OR REPLACE FUNCTION hafbe_endpoints.get_witness(account TEXT)
RETURNS hafbe_types.witness_setof -- noqa: LT01, CP05
LANGUAGE 'plpgsql'
STABLE
SET from_collapse_limit = 16
SET join_collapse_limit = 16
SET jit = OFF
AS
$$
BEGIN

PERFORM set_config('response.headers', '[{"Cache-Control": "public, max-age=2"}]', true);

RETURN (
WITH limited_set AS (
  SELECT
    cw.witness_id, av.name::TEXT AS witness,
    cw.url, cw.price_feed, cw.bias,
    (NOW() - cw.feed_updated_at)::INTERVAL AS feed_age,
    cw.block_size, cw.signing_key, cw.version,
    COALESCE(
      (
        SELECT count(*) as missed
        FROM hive.account_operations_view aov
        WHERE aov.op_type_id = 86 AND aov.account_id = cw.witness_id
      )::INT
    ,0) AS missed_blocks,
    COALESCE(cw.hbd_interest_rate, 0) AS hbd_interest_rate
  FROM hive.accounts_view av
  JOIN hafbe_app.current_witnesses cw ON av.id = cw.witness_id
  WHERE av.name = account
),
get_block_num AS MATERIALIZED
(SELECT bv.num AS block_num FROM hive.blocks_view bv ORDER BY bv.num DESC LIMIT 1)

SELECT ROW(
  ls.witness, 
  all_votes.rank, 
  ls.url,
  COALESCE(all_votes.votes, 0),
  (SELECT hive.get_vesting_balance((SELECT gbn.block_num FROM get_block_num gbn), COALESCE(all_votes.votes, 0)))::BIGINT, 
  COALESCE(wvcc.votes_daily_change, 0),
  (SELECT hive.get_vesting_balance((SELECT gbn.block_num FROM get_block_num gbn), COALESCE(wvcc.votes_daily_change, 0)))::BIGINT, 
  COALESCE(all_votes.voters_num, 0),
  COALESCE(wvcc.voters_num_daily_change, 0),
  ls.price_feed, 
  ls.bias, 
  ls.feed_age, 
  ls.block_size, 
  ls.signing_key, 
  ls.version,
  ls.missed_blocks, 
  ls.hbd_interest_rate
  )
FROM limited_set ls
LEFT JOIN hafbe_app.witness_votes_cache all_votes ON all_votes.witness_id = ls.witness_id 
LEFT JOIN hafbe_app.witness_votes_change_cache wvcc ON wvcc.witness_id = ls.witness_id

);

END
$$;

create or replace function hafbe_endpoints.root() returns json as $_$
declare
openapi json = $$
{
  "openapi": "3.1.0",
  "info": {
    "title": "HAF Block Explorer",
    "description": "HAF block explorer is an API for querying information about transactions/operations included in Hive blocks, as well as block producer (i.e. witness) information.",
    "license": {
      "name": "MIT License",
      "url": "https://opensource.org/license/mit"
    },
    "version": "1.27.5"
  },
  "externalDocs": {
    "description": "HAF Block Explorer gitlab repository",
    "url": "https://gitlab.syncad.com/hive/haf_block_explorer"
  },
  "tags": [
    {
      "name": "witnesses",
      "description": "Information about witnesses"
    }
  ],
  "servers": [
    {
      "url": "/"
    }
  ],
  "paths": {
    "/hafbe/witnesses": {
      "x-rewrite_url": "http://localhost:3000/rpc/get_witnesses",
      "get": {
        "tags": [
          "witnesses"
        ],
        "summary": "List witnesses",
        "description": "List all witnesses (both active and standby)",
        "operationId": "get_witnesses",
        "parameters": [
          {
            "in": "query",
            "name": "limit",
            "required": false,
            "schema": {
              "type": "integer"
            },
            "description": "for pagination, return at most `limit` witnesses"
          },
          {
            "in": "query",
            "name": "offset",
            "required": false,
            "schema": {
              "type": "integer"
            },
            "description": "for pagination, start at the `offset`th witness"
          },
          {
            "in": "query",
            "name": "sort",
            "required": false,
            "schema": {
              "$ref": "#/components/schemas/order_by_witness",
              "default": "votes"
            },
            "description": "Sort order:\n * `witness` - the witness' name\n * `rank` - their current rank (highest weight of votes => lowest rank)\n * `url` - the witness' url\n * `votes` - total number of votes\n * `votes_daily_change` - change in `votes` in the last 24 hours\n * `voters_num` - total number of voters approving the witness\n * `voters_num_daily_change` - change in `voters_num` in the last 24 hours\n * `price_feed` - their current published value for the HIVE/HBD price feed\n * `bias` - ?\n * `feed_age` - how old their feed value is\n * `block_size` - the block size they're voting for\n * `signing_key` - the witness' block-signing public key\n * `version` - the version of hived the witness is running\n"
          },
          {
            "in": "query",
            "name": "direction",
            "required": false,
            "schema": {
              "$ref": "#/components/schemas/sort_direction",
              "default": "desc"
            },
            "description": "Sort order:\n * `asc` - Ascending, from A to Z or smallest to largest\n * `desc` - Descending, from Z to A or largest to smallest\n"
          }
        ],
        "responses": {
          "200": {
            "description": "The list of witnesses",
            "content": {
              "application/json": {
                "schema": {
                  "$ref": "#/components/schemas/array_of_witnesses"
                },
                "example": [
                  {
                    "witness": "arcange",
                    "rank": 1,
                    "url": "https://peakd.com/witness-category/@arcange/witness-update-202103",
                    "vests": 141591182132060780,
                    "votes_hive_power": 81865807173,
                    "votes_daily_change": 39841911089,
                    "votes_daily_change_hive_power": 23036,
                    "voters_num": 4481,
                    "voters_num_daily_change": 5,
                    "price_feed": 0.302,
                    "bias": 0,
                    "feed_age": "00:45:20.244402",
                    "block_size": 65536,
                    "signing_key": "STM6wjYfYn728hR5yXNBS5GcMoACfYymKEWW1WFzDGiMaeo9qUKwH",
                    "version": "1.27.4",
                    "missed_blocks": 697,
                    "hbd_interest_rate": 2000
                  },
                  {
                    "witness": "gtg",
                    "rank": 2,
                    "url": "https://gtg.openhive.network",
                    "vests": 141435014237847520,
                    "votes_hive_power": 81775513339,
                    "votes_daily_change": 186512763933,
                    "votes_daily_change_hive_power": 107839,
                    "voters_num": 3131,
                    "voters_num_daily_change": 4,
                    "price_feed": 0.3,
                    "bias": 0,
                    "feed_age": "00:55:26.244402",
                    "block_size": 65536,
                    "signing_key": "STM5dLh5HxjjawY4Gm6o6ugmJUmEXgnfXXXRJPRTxRnvfFBJ24c1M",
                    "version": "1.27.5",
                    "missed_blocks": 986,
                    "hbd_interest_rate": 1500
                  }
                ]
              }
            }
          }
        }
      }
    },
    "/hafbe/witnesses/{account}": {
      "get": {
        "tags": [
          "witnesses"
        ],
        "summary": "Get a single witness",
        "description": "Return a single witness given their account name",
        "operationId": "get_witness",
        "parameters": [
          {
            "in": "path",
            "name": "account",
            "required": true,
            "schema": {
              "type": "string"
            },
            "description": "the witness account name"
          }
        ],
        "responses": {
          "200": {
            "description": "The witness",
            "content": {
              "application/json": {
                "schema": {
                  "$ref": "#/components/schemas/witness"
                },
                "example": {
                  "witness": "arcange",
                  "rank": 1,
                  "url": "https://peakd.com/witness-category/@arcange/witness-update-202103",
                  "vests": 141591182132060780,
                  "votes_hive_power": 81865807173,
                  "votes_daily_change": 39841911089,
                  "votes_daily_change_hive_power": 23036,
                  "voters_num": 4481,
                  "voters_num_daily_change": 5,
                  "price_feed": 0.302,
                  "bias": 0,
                  "feed_age": "00:45:20.244402",
                  "block_size": 65536,
                  "signing_key": "STM6wjYfYn728hR5yXNBS5GcMoACfYymKEWW1WFzDGiMaeo9qUKwH",
                  "version": "1.27.4",
                  "missed_blocks": 697,
                  "hbd_interest_rate": 2000
                }
              }
            }
          },
          "404": {
            "description": "No such witness"
          }
        }
      }
    },
    "/hafbe/witnesses/{account}/voters/count": {
      "get": {
        "tags": [
          "witnesses"
        ],
        "summary": "Get the number of voters for a witness",
        "description": "Get the number of voters for a witness given their account name",
        "operationId": "get_witness_voters_num",
        "parameters": [
          {
            "in": "path",
            "name": "account",
            "required": true,
            "schema": {
              "type": "string"
            },
            "description": "the witness account name"
          }
        ],
        "responses": {
          "200": {
            "description": "The number of voters currently voting for this witness",
            "content": {
              "application/json": {
                "schema": {
                  "type": "integer"
                },
                "example": 3131
              }
            }
          },
          "404": {
            "description": "No such witness"
          }
        }
      }
    },
    "/hafbe/witnesses/{account}/voters": {
      "get": {
        "tags": [
          "witnesses"
        ],
        "summary": "Get the of voters for a witness",
        "description": "Get information about the voters voting for a given witness",
        "operationId": "get_witness_voters",
        "parameters": [
          {
            "in": "path",
            "name": "account",
            "required": true,
            "schema": {
              "type": "string"
            },
            "description": "the witness account name"
          },
          {
            "in": "query",
            "name": "limit",
            "required": false,
            "schema": {
              "type": "integer",
              "default": 2147483647
            },
            "description": "return at most `limit` voters"
          },
          {
            "in": "query",
            "name": "sort",
            "required": false,
            "schema": {
              "$ref": "#/components/schemas/order_by_votes",
              "default": "vests"
            },
            "description": "Sort order:\n * `voter` - total number of voters casting their votes for each witness.  this probably makes no sense for call???\n * `vests` - total weight of vests casting their votes for each witness \n * `account_vests` - total weight of vests owned by accounts voting for each witness \n * `proxied_vests` - total weight of vests owned by accounts who proxy their votes to a voter voting for each witness\n * `timestamp` - the time the voter last changed their vote???\n"
          },
          {
            "in": "query",
            "name": "direction",
            "required": false,
            "schema": {
              "$ref": "#/components/schemas/sort_direction",
              "default": "desc"
            },
            "description": "Sort order:\n * `asc` - Ascending, from A to Z or smallest to largest\n * `desc` - Descending, from Z to A or largest to smallest\n"
          }
        ],
        "responses": {
          "200": {
            "description": "The number of voters currently voting for this witness",
            "content": {
              "application/json": {
                "schema": {
                  "$ref": "#/components/schemas/array_of_witness_voters"
                },
                "example": [
                  {
                    "voter": "reugie",
                    "vests": 1492852870616,
                    "vests_hive_power": 863149,
                    "account_vests": 1492852870616,
                    "account_hive_power": 863149,
                    "proxied_vests": 0,
                    "proxied_hive_power": 0,
                    "timestamp": "2024-03-27T14:46:09.000Z"
                  },
                  {
                    "voter": "cooperclub",
                    "vests": 8238935864379,
                    "vests_hive_power": 4763650,
                    "account_vests": 8238935864379,
                    "account_hive_power": 4763650,
                    "proxied_vests": 0,
                    "proxied_hive_power": 0,
                    "timestamp": "2024-03-27T14:42:06.000Z"
                  }
                ]
              }
            }
          },
          "404": {
            "description": "No such witness"
          }
        }
      }
    },
    "/hafbe/witnesses/{account}/votes/history": {
      "get": {
        "tags": [
          "witnesses"
        ],
        "summary": "Get the history of votes for this witness",
        "description": "Get information about each vote cast for this witness",
        "operationId": "get_witness_votes_history",
        "parameters": [
          {
            "in": "path",
            "name": "account",
            "required": true,
            "schema": {
              "type": "string"
            },
            "description": "the witness account name"
          },
          {
            "in": "query",
            "name": "limit",
            "required": false,
            "schema": {
              "type": "integer",
              "default": 100
            },
            "description": "return at most `limit` voters"
          },
          {
            "in": "query",
            "name": "sort",
            "required": false,
            "schema": {
              "$ref": "#/components/schemas/order_by_votes",
              "default": "timestamp"
            },
            "description": "Sort order:\n * `voter` - total number of voters casting their votes for each witness.  this probably makes no sense for call???\n * `vests` - total weight of vests casting their votes for each witness \n * `account_vests` - total weight of vests owned by accounts voting for each witness \n * `proxied_vests` - total weight of vests owned by accounts who proxy their votes to a voter voting for each witness\n * `timestamp` - the time the voter last changed their vote???\n"
          },
          {
            "in": "query",
            "name": "direction",
            "required": false,
            "schema": {
              "$ref": "#/components/schemas/sort_direction",
              "default": "desc"
            },
            "description": "Sort order:\n * `asc` - Ascending, from A to Z or smallest to largest\n * `desc` - Descending, from Z to A or largest to smallest\n"
          },
          {
            "in": "query",
            "name": "from_time",
            "required": false,
            "schema": {
              "type": "string",
              "format": "date-time"
            },
            "description": "return only votes newer than `from_time`"
          },
          {
            "in": "query",
            "name": "to_time",
            "required": false,
            "schema": {
              "type": "string",
              "format": "date-time"
            },
            "description": "return only votes older than `to_time`"
          }
        ],
        "responses": {
          "200": {
            "description": "The number of voters currently voting for this witness",
            "content": {
              "application/json": {
                "schema": {
                  "$ref": "#/components/schemas/array_of_witness_vote_history_records"
                },
                "example": [
                  {
                    "voter": "reugie",
                    "approve": true,
                    "vests": 1492852870616,
                    "vests_hive_power": 863149,
                    "account_vests": 1492852870616,
                    "account_hive_power": 863149,
                    "proxied_vests": 0,
                    "proxied_hive_power": 0,
                    "timestamp": "2024-03-27T14:46:09.000Z"
                  },
                  {
                    "voter": "cooperclub",
                    "approve": true,
                    "vests": 8238935864379,
                    "vests_hive_power": 4763650,
                    "account_vests": 8238935864379,
                    "account_hive_power": 4763650,
                    "proxied_vests": 0,
                    "proxied_hive_power": 0,
                    "timestamp": "2024-03-27T14:42:06.000Z"
                  }
                ]
              }
            }
          },
          "404": {
            "description": "No such witness"
          }
        }
      }
    }
  },
  "components": {
    "schemas": {
      "order_by_votes": {
        "type": "string",
        "enum": [
          "voter",
          "vests",
          "account_vests",
          "proxied_vests",
          "timestamp"
        ]
      },
      "order_by_witness": {
        "type": "string",
        "enum": [
          "witness",
          "rank",
          "url",
          "votes",
          "votes_daily_change",
          "voters_num",
          "voters_num_daily_change",
          "price_feed",
          "bias",
          "feed_age",
          "block_size",
          "signing_key",
          "version"
        ]
      },
      "sort_direction": {
        "type": "string",
        "enum": [
          "asc",
          "desc"
        ]
      },
      "witness": {
        "type": "object",
        "properties": {
          "witness": {
            "type": "string",
            "description": "the name of the witness account"
          },
          "rank": {
            "type": "integer",
            "description": "the current rank of the witness according to the votes cast on the    blockchain.  The top 20 witnesses (ranks 1 - 20) will produce blocks each round."
          },
          "url": {
            "type": "string",
            "description": "the witness's home page"
          },
          "vests": {
            "type": "integer",
            "description": "the total weight of votes cast in favor of this witness, expressed in VESTS"
          },
          "votes_hive_power": {
            "type": "integer",
            "description": "the total weight of votes cast in favor of this witness, expressed in HIVE power, at the current ratio"
          },
          "votes_daily_change": {
            "type": "integer",
            "description": "the increase or decrease in votes for this witness over the last 24 hours, expressed in vests"
          },
          "votes_daily_change_hive_power": {
            "type": "integer",
            "description": "the increase or decrease in votes for this witness over the last 24 hours, expressed in HIVE power, at the current ratio"
          },
          "voters_num": {
            "type": "integer",
            "description": "the number of voters supporting this witness"
          },
          "voters_num_daily_change": {
            "type": "integer",
            "description": "the increase or decrease in the number of voters voting for this witness over the last 24 hours"
          },
          "price_feed": {
            "type": "number",
            "description": "the current price feed provided by the witness in HIVE/HBD"
          },
          "bias": {
            "type": "integer",
            "description": "no clue"
          },
          "feed_age": {
            "type": "string",
            "description": "how old the witness price feed is (as a string formatted hh:mm:ss.ssssss)"
          },
          "block_size": {
            "type": "integer",
            "description": "the maximum block size the witness is currently voting for, in bytes"
          },
          "signing_key": {
            "type": "string",
            "description": "the key used to verify blocks signed by this witness"
          },
          "version": {
            "type": "string",
            "description": "the version of hived the witness is running"
          },
          "missed_blocks": {
            "type": "integer",
            "description": "the number of blocks the witness should have generated but didn't (over the entire lifetime of the blockchain)"
          },
          "hbd_interest_rate": {
            "type": "number",
            "description": "the interest rate the witness is voting for"
          }
        }
      },
      "array_of_witnesses": {
        "type": "array",
        "items": {
          "$ref": "#/components/schemas/witness"
        }
      },
      "witness_voter": {
        "type": "object",
        "properties": {
          "voter": {
            "type": "string",
            "description": "account name of the voter"
          },
          "vests": {
            "type": "integer",
            "description": "number of vests this voter is directly voting with"
          },
          "votes_hive_power": {
            "type": "integer",
            "description": "number of vests this voter is directly voting with, expressed in HIVE power, at the current ratio"
          },
          "account_vests": {
            "type": "integer",
            "description": "number of vests in the voter's account.  if some vests are delegated, they will not be counted in voting"
          },
          "account_hive_power": {
            "type": "integer",
            "description": "number of vests in the voter's account, expressed in HIVE power, at the current ratio.  if some vests are delegated, they will not be counted in voting"
          },
          "proxied_vests": {
            "type": "integer",
            "description": "the number of vests proxied to this account"
          },
          "proxied_hive_power": {
            "type": "integer",
            "description": "the number of vests proxied to this account expressed in HIVE power, at the current ratio"
          },
          "timestamp": {
            "type": "string",
            "format": "date-time",
            "description": "the time this account last changed its voting power"
          }
        }
      },
      "array_of_witness_voters": {
        "type": "array",
        "items": {
          "$ref": "#/components/schemas/witness_voter"
        }
      },
      "witness_vote_history_record": {
        "type": "object",
        "properties": {
          "voter": {
            "type": "string",
            "description": "account name of the voter"
          },
          "approve": {
            "type": "boolean",
            "description": "whether the voter approved or rejected the witness"
          },
          "vests": {
            "type": "integer",
            "description": "number of vests this voter is directly voting with"
          },
          "votes_hive_power": {
            "type": "integer",
            "description": "number of vests this voter is directly voting with, expressed in HIVE power, at the current ratio"
          },
          "account_vests": {
            "type": "integer",
            "description": "number of vests in the voter's account.  if some vests are delegated, they will not be counted in voting"
          },
          "account_hive_power": {
            "type": "integer",
            "description": "number of vests in the voter's account, expressed in HIVE power, at the current ratio.  if some vests are delegated, they will not be counted in voting"
          },
          "proxied_vests": {
            "type": "integer",
            "description": "the number of vests proxied to this account"
          },
          "proxied_hive_power": {
            "type": "integer",
            "description": "the number of vests proxied to this account expressed in HIVE power, at the current ratio"
          },
          "timestamp": {
            "type": "string",
            "format": "date-time",
            "description": "the time of the vote change"
          }
        }
      },
      "array_of_witness_vote_history_records": {
        "type": "array",
        "items": {
          "$ref": "#/components/schemas/witness_vote_history_record"
        }
      }
    }
  }
}
$$;
begin
  return openapi;
end
$_$ language plpgsql;

RESET ROLE;
