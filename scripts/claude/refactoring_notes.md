# Processing Functions Refactoring Notes

Lessons learned from refactoring `process_account_stats.sql` to guide future refactoring.

## Completed: process_account_stats.sql

### Files Modified
1. `db/process_account_stats.sql` - Main processing function
2. `backend/operation_parsers/account_operations.sql` - Helper parsing functions

### Key Changes Made

#### 1. Replaced Recursive CTE with Window Functions
```sql
-- To get first non-NULL value:
FIRST_VALUE(field) OVER (
  PARTITION BY account_id
  ORDER BY CASE WHEN field IS NOT NULL THEN 0 ELSE 1 END, source_op
)

-- To get last non-NULL value (DESC order):
FIRST_VALUE(field) OVER (
  PARTITION BY account_id
  ORDER BY CASE WHEN field IS NOT NULL THEN 0 ELSE 1 END, source_op DESC
)
```

#### 2. Replaced Correlated Subqueries with JOINs
```sql
-- Before:
SELECT (SELECT av.id FROM hafbe_app.accounts_view av WHERE av.name = account_name) AS account_id
FROM parsed_ops

-- After:
SELECT av.id AS account_id
FROM parsed_ops po
JOIN hafbe_app.accounts_view av ON av.name = po.account_name
```

#### 3. Cached Operation Type IDs in DECLARE Block
```sql
DECLARE
  _op_pow  INT := hafbe_backend.op_pow();
  _op_pow2 INT := hafbe_backend.op_pow2();
  -- etc.
```

#### 4. Use operations_view_extended for timestamp
Use `hafbe_app.operations_view_extended` which has `timestamp` column - avoids extra join to blocks_view.

#### 5. Use plpgsql for Helper Functions
Always use `LANGUAGE 'plpgsql' STABLE` for helper functions, not `LANGUAGE sql`.
This provides consistent behavior and allows for DECLARE blocks with local variables.

---

## Comment Style (Based on btracker/process_balances.sql)

### File Header
Brief 3-4 line description at the top of the function:
```sql
/*
 * function_name: Brief description of what this function does.
 *
 * Core operations: List of main tasks performed. Updates target_table
 * with processed values.
 */
```

### Section Headers
Use for major logical sections within the function:
```sql
/*
 * ===================================================================================
 * SECTION N: Section Title
 * ===================================================================================
 * Brief description of what this section handles and why.
 */
```

### CTE Comments
Place BEFORE each CTE with this structure:
```sql
/*
 * ===================================================================================
 * CTE: cte_name
 * ===================================================================================
 * WHY MATERIALIZED: Explanation of why MATERIALIZED is needed.
 *   - Prevents repeated execution of expensive operations
 *   - Used by multiple downstream CTEs
 *   - Contains expensive JOINs or aggregations
 *
 * PURPOSE: What this CTE accomplishes.
 *
 * DATA FLOW:
 *   1. Step one - what happens first
 *   2. Step two - next transformation
 *   3. Step three - final output
 *
 * EXAMPLE:
 *   Input data:
 *   | col1 | col2 | col3 |
 *   |------|------|------|
 *   | a    | 100  | x    |
 *   | b    | 200  | y    |
 *
 *   Output:
 *   | result_col | computed_col |
 *   |------------|--------------|
 *   | a          | 300          |
 */
```

### Pattern Documentation
Document common SQL patterns inline:
```sql
/*
 * PATTERN NAME:
 *   Code snippet showing the pattern
 *
 * Explanation of how the pattern works:
 *   - Point 1
 *   - Point 2
 */
```

### Common Patterns to Document

#### "Last Operation Wins" Pattern
```sql
/*
 * "LAST OPERATION WINS" PATTERN:
 *   ROW_NUMBER() OVER (PARTITION BY account_id ORDER BY source_op DESC)
 *
 *   By ordering DESC, rn=1 identifies the MOST RECENT operation.
 *   WHERE rn = 1 filters to only the latest.
 */
```

#### UPSERT Pattern
```sql
/*
 * UPSERT with COALESCE for incremental updates:
 *   COALESCE(EXCLUDED.field, ap.field, DEFAULT)
 *
 * Three-argument COALESCE:
 *   1. EXCLUDED.field: New value from this batch
 *   2. ap.field: Existing value in table
 *   3. DEFAULT: Fallback if both are NULL
 */
```

#### Additive UPSERT Pattern
```sql
/*
 * ADDITIVE UPSERT PATTERN:
 *   DO UPDATE SET count = existing.count + EXCLUDED.count
 *
 * Unlike replacement, here we ADD the new delta to existing value.
 */
```

---

## Indentation

- **2 spaces** for SQL code body
- **4 spaces** only for function parameter listings
- Align DECLARE block variable names for readability

---

## Return Type Pattern

**Prefer named variables over inline `RETURN ROW(...)`** for better readability.

Instead of:
```sql
BEGIN
  RETURN ROW(
    _body -> 'value' ->> 'worker_account',
    TRUE,
    NULL,
    _timestamp
  )::hafbe_backend.impacted_account_parameters;
END
```

Use a declared variable:
```sql
DECLARE
  __result hafbe_backend.impacted_account_parameters;
BEGIN
  __result := (
    _body -> 'value' ->> 'worker_account',
    TRUE,
    NULL,
    _timestamp
  );

  RETURN __result;
END
```

Benefits:
- More readable - clear what type is being returned
- Easier to debug - can inspect variable before return
- Self-documenting - variable name describes purpose

---

## UPSERT Column Alignment

**Align `=` signs in DO UPDATE SET** for readability.

Instead of:
```sql
DO UPDATE SET
  mined = COALESCE(EXCLUDED.mined, ap.mined, hafbe_backend.default_mined()),
  recovery_account = COALESCE(EXCLUDED.recovery_account, ap.recovery_account, hafbe_backend.default_recovery_account()),
  created = COALESCE(EXCLUDED.created, ap.created, hafbe_backend.default_timestamp());
```

Use aligned columns:
```sql
DO UPDATE SET
  mined            = COALESCE(EXCLUDED.mined, ap.mined, hafbe_backend.default_mined()),
  recovery_account = COALESCE(EXCLUDED.recovery_account, ap.recovery_account, hafbe_backend.default_recovery_account()),
  created          = COALESCE(EXCLUDED.created, ap.created, hafbe_backend.default_timestamp());
```

Rules:
- Pad column names to match the longest column
- Single space before and after `=`
- Applies to INSERT column lists, UPDATE SET clauses, and variable assignments

---

## Table Column Formatting

Align table columns so types and constraints form vertical columns:
```sql
CREATE TABLE IF NOT EXISTS hafbe_app.account_parameters
(
  account                  INT       NOT NULL,
  can_vote                 BOOLEAN   NULL,
  mined                    BOOLEAN   NULL,
  recovery_account         TEXT      NULL,
  last_account_recovery    TIMESTAMP NULL,
  created                  TIMESTAMP NULL,
  pending_claimed_accounts INT       NULL,

  CONSTRAINT pk_account_parameters PRIMARY KEY (account)
);
```

Rules:
- **Column names** padded to consistent width (based on longest name)
- **Types** padded to consistent width (e.g., 9 chars)
- **Always specify NULL or NOT NULL** explicitly for every column
- One blank line before CONSTRAINT definitions

---

## Views

### Schema Selection
- **Processing functions:** Use context views (`hafbe_app.*_view`)
- **API functions:** Use hive views (`hive.*_view`)

### operations_view vs operations_view_extended

**Use `operations_view_extended` ONLY when timestamp is needed.**

The `_extended` view includes a JOIN to get the timestamp column, which adds overhead.
If you don't need the timestamp, use the regular `operations_view`:

```sql
-- GOOD: Need timestamp for recovery_timestamp
FROM hafbe_app.operations_view_extended ov
SELECT ov.timestamp AS recovery_timestamp

-- BAD: Don't need timestamp, wasting JOIN overhead
FROM hafbe_app.operations_view_extended ov
SELECT av.id, NOT (ov.body -> 'value' ->> 'decline')::BOOLEAN

-- GOOD: No timestamp needed, use regular view
FROM hafbe_app.operations_view ov
SELECT av.id, NOT (ov.body -> 'value' ->> 'decline')::BOOLEAN
```

---

## accounts_view Performance

### Use Subquery Instead of JOIN

Due to `hafbe_app.accounts_view` internal structure, using it in a **subquery performs
better than a JOIN**. The view structure causes performance issues with JOIN optimization.

```sql
-- PREFERRED: Subquery pattern
SELECT
  (SELECT av.id FROM hafbe_app.accounts_view av WHERE av.name = po.account_name) AS account_id,
  po.field1,
  po.field2
FROM parsed_operations po

-- AVOID: JOIN pattern (performance issues with this view)
SELECT
  av.id AS account_id,
  po.field1,
  po.field2
FROM parsed_operations po
JOIN hafbe_app.accounts_view av ON av.name = po.account_name
```

### Late Binding (Resolve IDs on Smallest CTE)

Resolve account names to IDs as **late as possible** - on the smallest/most filtered CTE.
This minimizes the number of lookups.

```sql
-- BAD: Resolving account_id early on large CTE
WITH parsed_operations AS MATERIALIZED (
  SELECT account_name, field1, source_op FROM ...  -- Many rows
),
operations_with_ids AS MATERIALIZED (
  SELECT
    (SELECT av.id FROM hafbe_app.accounts_view av WHERE av.name = po.account_name) AS account_id,
    po.field1
  FROM parsed_operations po  -- Still many rows!
),
final_values AS (
  SELECT DISTINCT ON (account_id) ...  -- Now reduced to one per account
  FROM operations_with_ids
)

-- GOOD: Resolving account_id late on smallest CTE
WITH parsed_operations AS MATERIALIZED (
  SELECT account_name, field1, source_op FROM ...  -- Many rows
),
aggregated AS (
  SELECT DISTINCT ON (account_name)  -- Now reduced to one per account
    account_name, field1
  FROM parsed_operations
  ORDER BY account_name, source_op DESC
)
SELECT
  (SELECT av.id FROM hafbe_app.accounts_view av WHERE av.name = a.account_name) AS account_id,
  a.field1
FROM aggregated a  -- Few rows, few lookups!
```

---

## JSON Parsing in Helper Functions

**Always use helper functions for JSON parsing instead of inline parsing in CTEs.**

Benefits:
- Centralized parsing logic - easier to maintain and debug
- Self-documenting - function name describes what's being extracted
- Reusable - same parser can be used across multiple processing functions
- Testable - can unit test parsers independently

```sql
-- BAD: Inline JSON parsing in CTE
WITH recovery_operations AS MATERIALIZED (
  SELECT
    ov.body -> 'value' ->> 'account_to_recover' AS account_name,
    ov.timestamp AS recovery_timestamp
  FROM hafbe_app.operations_view_extended ov
  WHERE ...
)

-- GOOD: Use helper function with CROSS JOIN (implicit LATERAL)
WITH recovery_operations AS MATERIALIZED (
  SELECT
    parsed.account_name,
    parsed.recovery_timestamp,
    ov.id AS source_op
  FROM hafbe_app.operations_view_extended ov
  CROSS JOIN hafbe_backend.parse_recover_account_operation(ov.body, ov.timestamp) parsed
  WHERE ...
)
```

Note: Functions in FROM clause are implicitly LATERAL in PostgreSQL, so
`CROSS JOIN func() alias` is cleaner than `CROSS JOIN LATERAL (SELECT (func()).*)`.


Helper functions should:
- Live in `backend/operation_parsers/*.sql`
- Return a composite type with all extracted fields
- Use `LANGUAGE 'plpgsql' STABLE`
- Include documentation of JSON structure

---

## Variable Initialization in DECLARE

Move queries into DECLARE when possible:
```sql
DECLARE
  _hf11_block INT := (SELECT block_num FROM hafd.applied_hardforks WHERE hardfork_num = 11);
```

---

## Constants Framework

All hardcoded default values should be centralized in `backend/utilities/constants.sql`.

### Account Defaults
| Constant Function | Value | Used For |
|-------------------|-------|----------|
| `hafbe_backend.default_can_vote()` | `TRUE` | Default voting ability |
| `hafbe_backend.default_mined()` | `TRUE` | Default mined status |
| `hafbe_backend.default_recovery_account()` | `''` | No recovery account |
| `hafbe_backend.default_timestamp()` | `'1970-01-01T00:00:00'` | Epoch placeholder |
| `hafbe_backend.default_pending_claimed_accounts()` | `0` | No pending accounts |

### Blockchain Account Names
| Constant Function | Value | Purpose |
|-------------------|-------|---------|
| `hafbe_backend.pre_hf11_recovery_account()` | `'steem'` | Pre-HF11 default recovery |
| `hafbe_backend.temp_creator_account()` | `'temp'` | Self-created account marker |

### Pattern: NULL in Tables, COALESCE in API

**Tables store only what we know** - columns allow NULL to indicate "unknown/not processed".
**API layer provides defaults** via COALESCE with constants.

Table definition (no DEFAULTs):
```sql
CREATE TABLE hafbe_app.account_parameters (
  account INT NOT NULL,
  can_vote BOOLEAN,           -- NULL = unknown
  mined BOOLEAN,              -- NULL = unknown
  recovery_account TEXT,      -- NULL = unknown
  ...
);
```

API endpoint uses COALESCE with constants:
```sql
COALESCE(_result.can_vote, hafbe_backend.default_can_vote()),
COALESCE(_result.mined, hafbe_backend.default_mined()),
COALESCE(_result.recovery_account, hafbe_backend.default_recovery_account()),
```

Processing functions can also use COALESCE for UPSERT fallbacks:
```sql
COALESCE(EXCLUDED.mined, ap.mined, hafbe_backend.default_mined())
```

---

## Common Issues to Look For

1. **Recursive CTEs for sequential processing** → Replace with window functions
2. **Correlated subqueries for general lookups** → Use JOINs (EXCEPT for accounts_view - see below)
3. **Repeated op_*() calls** → Cache in DECLARE
4. **ROW_NUMBER partitioned by JSON field** → Aggregate first, partition by account_name
5. **Missing MATERIALIZED** → Add to CTEs that are expensive or referenced multiple times
6. **Joining blocks_view for timestamp** → Use operations_view_extended
7. **Hardcoded default values** → Use constants from `backend/utilities/constants.sql`
8. **Using operations_view_extended without timestamp** → Use operations_view instead
9. **JOIN on accounts_view** → Use subquery pattern instead (view structure issue)
10. **Resolving account IDs early** → Resolve on smallest CTE (late binding)
11. **Inline JSON parsing in CTEs** → Use helper functions from `backend/operation_parsers/`

---

## Code Templates

### Processing Function
```sql
SET ROLE hafbe_owner;

/*
 * function_name: Brief description of what this function processes.
 *
 * Core operations: List main tasks. Updates target_table with results.
 */
CREATE OR REPLACE FUNCTION hafbe_app.process_xyz(_from INT, _to INT)
RETURNS VOID
LANGUAGE 'plpgsql' VOLATILE
SET from_collapse_limit = 16
SET join_collapse_limit = 16
SET jit = OFF
AS
$$
DECLARE
  _hf_block INT := (SELECT block_num FROM hafd.applied_hardforks WHERE hardfork_num = X);
  _op_type1 INT := hafbe_backend.op_type1();
  _op_type2 INT := hafbe_backend.op_type2();
BEGIN

  /*
   * ===================================================================================
   * SECTION 1: Section Title
   * ===================================================================================
   * Brief description of what this section handles.
   */

  /*
   * ===================================================================================
   * CTE: operations
   * ===================================================================================
   * WHY MATERIALIZED: Expensive JSON parsing, used by downstream CTEs.
   *
   * PURPOSE: Fetch and parse operations from the block range.
   */
  WITH operations AS MATERIALIZED (
    SELECT ...
    FROM hafbe_app.operations_view_extended ov
    WHERE ov.op_type_id IN (_op_type1, _op_type2)
      AND ov.block_num BETWEEN _from AND _to
  ),

  /*
   * ===================================================================================
   * CTE: with_ids
   * ===================================================================================
   * WHY MATERIALIZED: JOIN result used by final_values.
   *
   * PURPOSE: Resolve account names to numeric IDs.
   */
  with_ids AS MATERIALIZED (
    SELECT av.id AS account_id, ...
    FROM operations o
    JOIN hafbe_app.accounts_view av ON av.name = o.account_name
  ),

  /*
   * ===================================================================================
   * CTE: final_values
   * ===================================================================================
   * PURPOSE: Calculate final values per account using window functions.
   */
  final_values AS MATERIALIZED (
    SELECT DISTINCT ON (account_id) ...
    FROM with_ids
    ORDER BY account_id
  )

  /*
   * UPSERT PATTERN:
   *   COALESCE(EXCLUDED.field, ap.field, DEFAULT)
   */
  INSERT INTO target_table (...)
  SELECT ...
  FROM final_values
  ON CONFLICT ... DO UPDATE SET ...;

END
$$;

RESET ROLE;
```

### Helper Function
```sql
/*
 * ===================================================================================
 * parse_xyz_operation
 * ===================================================================================
 * PURPOSE: Brief description of what this parser does.
 *
 * JSON STRUCTURE:
 *   { "value": { "field1": "...", "field2": "..." } }
 *
 * RETURNS:
 *   - field1: Description
 *   - field2: Description
 */
CREATE OR REPLACE FUNCTION hafbe_backend.parse_xyz_operation(
    _body      JSONB,
    _timestamp TIMESTAMP
)
RETURNS hafbe_backend.return_type
LANGUAGE 'plpgsql' STABLE
AS $$
DECLARE
  __result hafbe_backend.return_type;
BEGIN
  __result := (
    _body -> 'value' ->> 'field1',
    _body -> 'value' ->> 'field2'
  );

  RETURN __result;
END
$$;
```

---

## Files to Check for Dependencies

1. `backend/operation_parsers/*.sql` - Helper parsing functions
2. `backend/utilities/operation_types.sql` - Operation type ID functions
3. `backend/utilities/constants.sql` - Default value constants
4. `db/hafbe_app.sql` - Target table definitions
5. `scripts/install_app.sh` - Installation order

---

## Hardfork Considerations

- **HF11:** Recovery account logic changed (see `parse_account_created_operation`)
- Query hardfork block: `(SELECT block_num FROM hafd.applied_hardforks WHERE hardfork_num = N)`
- Conditional: `ho.block_num > _hf_block`

---

## Next Files to Refactor

1. `db/process_witness_stats.sql` - Most complex, similar patterns
2. `db/process_witness_votes.sql` - Uses helper functions heavily
3. `db/process_transaction_stats.sql` - Simpler structure
4. `db/process_block_operations.sql` - Already clean
