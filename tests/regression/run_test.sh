#!/usr/bin/env bash
# =============================================================================
# HAF Block Explorer Regression Test
# =============================================================================
#
# PURPOSE:
#   Compares HAF Block Explorer's computed account and witness data against
#   expected values from a hived node snapshot to detect regressions.
#
# WORKFLOW:
#   1. Install the regression test schema (hafbe_test)
#   2. Clear any previous test data
#   3. Decompress the fixture data
#   4. Load expected values into the database
#   5. Run comparison and check for discrepancies
#
# PREREQUISITES:
#   - HAF Block Explorer schema must be installed and synced
#   - accounts_dump.json.gz and/or witnesses_dump.json.gz fixtures must exist
#
# EXIT CODES:
#   0 - All data matches
#   1 - One or more accounts/witnesses have discrepancies
#
# -----------------------------------------------------------------------------
# RECREATING THE FIXTURES
# -----------------------------------------------------------------------------
#
# ACCOUNTS (accounts_dump.json.gz):
#   The fixture contains account data from hived's database_api.list_accounts.
#   To create a new fixture:
#
#   1. Configure hived with: api-limit = 10000000
#   2. Sync hived to target block height
#   3. curl -s -o accounts_dump.json \
#        --data '{"jsonrpc":"2.0", "method":"database_api.list_accounts", \
#                 "params": {"start":"", "limit":10000000, "order":"by_name"}, \
#                 "id":1}' "http://localhost:8091"
#   4. sed -i "s/'//g" accounts_dump.json
#   5. gzip accounts_dump.json
#
# WITNESSES (witnesses_dump.json.gz):
#   Similar process using database_api.list_witnesses endpoint.
#
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default configuration
POSTGRES_HOST="${POSTGRES_HOST:-localhost}"
POSTGRES_PORT="${POSTGRES_PORT:-5432}"
POSTGRES_USER="${POSTGRES_USER:-haf_admin}"
HAFBE_SCHEMA="${HAFBE_SCHEMA:-hafbe_app}"
TEST_TYPE="${TEST_TYPE:-all}"

print_help() {
    cat <<EOF
Usage: $0 [OPTIONS]

Runs regression test comparing HAF Block Explorer values against expected snapshot.

OPTIONS:
    --host=HOSTNAME     PostgreSQL hostname (default: localhost)
    --port=NUMBER       PostgreSQL port (default: 5432)
    --user=USERNAME     PostgreSQL user (default: haf_admin)
    --schema=SCHEMA     HAF Block Explorer schema name (default: hafbe_app)
    --type=TYPE         Test type: account, witness, or all (default: all)
    --help              Show this help message
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --host=*)
            POSTGRES_HOST="${1#*=}"
            ;;
        --port=*)
            POSTGRES_PORT="${1#*=}"
            ;;
        --user=*)
            POSTGRES_USER="${1#*=}"
            ;;
        --schema=*)
            HAFBE_SCHEMA="${1#*=}"
            ;;
        --type=*)
            TEST_TYPE="${1#*=}"
            ;;
        --help|-h)
            print_help
            exit 0
            ;;
        *)
            echo "ERROR: Unknown option: $1"
            print_help
            exit 1
            ;;
    esac
    shift
done

POSTGRES_ACCESS="postgresql://$POSTGRES_USER@$POSTGRES_HOST:$POSTGRES_PORT/haf_block_log"

echo "=============================================="
echo "HAF Block Explorer Regression Test"
echo "=============================================="
echo "  Host: $POSTGRES_HOST:$POSTGRES_PORT"
echo "  User: $POSTGRES_USER"
echo "  Schema: $HAFBE_SCHEMA"
echo "  Test Type: $TEST_TYPE"
echo ""

# Set up timestamping for logs
if command -v ts > /dev/null 2>&1; then
    timestamper="ts '%Y-%m-%d %H:%M:%.S'"
elif command -v tai64nlocal > /dev/null 2>&1; then
    timestamper="tai64n | tai64nlocal"
else
    timestamper="cat"
fi

# -----------------------------------------------------------------------------
# Step 1: Install regression test schema
# -----------------------------------------------------------------------------
echo "Step 1: Installing regression test schema..."
"$SCRIPT_DIR/install_test_schema.sh" \
    --host="$POSTGRES_HOST" \
    --port="$POSTGRES_PORT" \
    --user="$POSTGRES_USER"
echo ""

# Track overall test result
OVERALL_RESULT=0

# -----------------------------------------------------------------------------
# Account Tests
# -----------------------------------------------------------------------------
if [ "$TEST_TYPE" = "account" ] || [ "$TEST_TYPE" = "all" ]; then
    echo "=============================================="
    echo "Running Account Regression Tests"
    echo "=============================================="

    # Step 2a: Clear previous account test data
    echo "Step 2a: Clearing previous account test data..."
    psql "$POSTGRES_ACCESS" -v "ON_ERROR_STOP=on" \
        -c "TRUNCATE hafbe_test.expected_account_stats;"
    psql "$POSTGRES_ACCESS" -v "ON_ERROR_STOP=on" \
        -c "TRUNCATE hafbe_test.differing_accounts;"
    echo ""

    # Step 3a: Decompress account fixture data
    echo "Step 3a: Preparing account fixture data..."
    rm -f "$SCRIPT_DIR/accounts_dump.json"

    if [ ! -f "$SCRIPT_DIR/accounts_dump.json.gz" ]; then
        echo "ERROR: Fixture file not found: $SCRIPT_DIR/accounts_dump.json.gz"
        exit 1
    fi

    gunzip -k "$SCRIPT_DIR/accounts_dump.json.gz" 2>/dev/null || \
        gunzip -c "$SCRIPT_DIR/accounts_dump.json.gz" > "$SCRIPT_DIR/accounts_dump.json"
    echo "  Decompressed accounts_dump.json"
    echo ""

    # Step 4a: Install psycopg2 if needed (not in CI)
    if [[ -z "${CI:-}" ]]; then
        echo "Step 4a: Installing Python dependencies..."
        pip install psycopg2-binary --quiet --break-system-packages
        echo ""
    fi

    # Step 5a: Load expected account data
    echo "Step 5a: Loading expected account data..."
    python3 "$SCRIPT_DIR/load_expected_data.py" \
        "$SCRIPT_DIR" \
        --host "$POSTGRES_HOST" \
        --port "$POSTGRES_PORT" \
        --user "$POSTGRES_USER" \
        --type account
    echo ""

    # Step 6a: Run account comparison
    echo "Step 6a: Comparing accounts..."
    psql "$POSTGRES_ACCESS" -v "ON_ERROR_STOP=on" \
        -c "SET SEARCH_PATH TO ${HAFBE_SCHEMA};" \
        -c "SELECT hafbe_test.compare_accounts();" \
        2>&1 | tee -i >(eval "$timestamper" >> "$SCRIPT_DIR/regression_test.log")
    echo ""

    # Step 7a: Check account results
    echo "Step 7a: Checking account results..."
    DIFFERING_ACCOUNTS=$(psql "$POSTGRES_ACCESS" -v "ON_ERROR_STOP=on" -t -A \
        -c "SELECT COUNT(*) FROM hafbe_test.differing_accounts;")

    if [ "$DIFFERING_ACCOUNTS" -eq 0 ]; then
        echo "  SUCCESS: All account data matches!"
    else
        echo "  FAILURE: $DIFFERING_ACCOUNTS accounts have discrepancies"
        psql "$POSTGRES_ACCESS" -v "ON_ERROR_STOP=on" \
            -c "SELECT * FROM hafbe_test.differing_accounts LIMIT 20;"
        echo "  Use hafbe_test.get_account_comparison(account_id) to debug."
        OVERALL_RESULT=1
    fi
    echo ""

    # Cleanup decompressed file
    rm -f "$SCRIPT_DIR/accounts_dump.json"
fi

# -----------------------------------------------------------------------------
# Witness Tests
# -----------------------------------------------------------------------------
if [ "$TEST_TYPE" = "witness" ] || [ "$TEST_TYPE" = "all" ]; then
    echo "=============================================="
    echo "Running Witness Regression Tests"
    echo "=============================================="

    # Step 2b: Clear previous witness test data
    echo "Step 2b: Clearing previous witness test data..."
    psql "$POSTGRES_ACCESS" -v "ON_ERROR_STOP=on" \
        -c "TRUNCATE hafbe_test.expected_witness_props;"
    psql "$POSTGRES_ACCESS" -v "ON_ERROR_STOP=on" \
        -c "TRUNCATE hafbe_test.differing_witnesses;"
    echo ""

    # Step 3b: Decompress witness fixture data
    echo "Step 3b: Preparing witness fixture data..."
    rm -f "$SCRIPT_DIR/witnesses_dump.json"

    if [ ! -f "$SCRIPT_DIR/witnesses_dump.json.gz" ]; then
        echo "ERROR: Fixture file not found: $SCRIPT_DIR/witnesses_dump.json.gz"
        exit 1
    fi

    gunzip -k "$SCRIPT_DIR/witnesses_dump.json.gz" 2>/dev/null || \
        gunzip -c "$SCRIPT_DIR/witnesses_dump.json.gz" > "$SCRIPT_DIR/witnesses_dump.json"
    echo "  Decompressed witnesses_dump.json"
    echo ""

    # Step 4b: Install psycopg2 if needed (not in CI)
    if [[ -z "${CI:-}" ]]; then
        echo "Step 4b: Installing Python dependencies..."
        pip install psycopg2-binary --quiet --break-system-packages
        echo ""
    fi

    # Step 5b: Load expected witness data
    echo "Step 5b: Loading expected witness data..."
    python3 "$SCRIPT_DIR/load_expected_data.py" \
        "$SCRIPT_DIR" \
        --host "$POSTGRES_HOST" \
        --port "$POSTGRES_PORT" \
        --user "$POSTGRES_USER" \
        --type witness
    echo ""

    # Step 6b: Run witness comparison
    echo "Step 6b: Comparing witnesses..."
    psql "$POSTGRES_ACCESS" -v "ON_ERROR_STOP=on" \
        -c "SET SEARCH_PATH TO hafbe_bal;" \
        -c "SELECT hafbe_test.compare_witnesses();" \
        2>&1 | tee -i >(eval "$timestamper" >> "$SCRIPT_DIR/regression_test.log")
    echo ""

    # Step 7b: Check witness results
    echo "Step 7b: Checking witness results..."
    DIFFERING_WITNESSES=$(psql "$POSTGRES_ACCESS" -v "ON_ERROR_STOP=on" -t -A \
        -c "SELECT COUNT(*) FROM hafbe_test.differing_witnesses;")

    if [ "$DIFFERING_WITNESSES" -eq 0 ]; then
        echo "  SUCCESS: All witness data matches!"
    else
        echo "  FAILURE: $DIFFERING_WITNESSES witnesses have discrepancies"
        psql "$POSTGRES_ACCESS" -v "ON_ERROR_STOP=on" \
            -c "SELECT * FROM hafbe_test.differing_witnesses LIMIT 20;"
        echo "  Use hafbe_test.get_witness_comparison(witness_id) to debug."
        OVERALL_RESULT=1
    fi
    echo ""

    # Cleanup decompressed file
    rm -f "$SCRIPT_DIR/witnesses_dump.json"
fi

# -----------------------------------------------------------------------------
# Final Results
# -----------------------------------------------------------------------------
echo "=============================================="
if [ "$OVERALL_RESULT" -eq 0 ]; then
    echo "SUCCESS: All regression tests passed!"
else
    echo "FAILURE: Some regression tests failed"
fi
echo "=============================================="

exit "$OVERALL_RESULT"
