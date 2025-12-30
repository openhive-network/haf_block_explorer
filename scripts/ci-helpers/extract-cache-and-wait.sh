#!/bin/bash
# Extract HAF Block Explorer sync cache and prepare for testing.
#
# This script handles cache extraction from NFS with proper race condition
# handling using marker files. It's designed to be called before starting
# docker-compose in test jobs.
#
# Usage:
#   extract-cache-and-wait.sh <cache-type> <cache-key> <dest-dir>
#
# Arguments:
#   cache-type  - Cache type (e.g., haf_hafbe_sync)
#   cache-key   - Cache key (e.g., ${HAF_COMMIT}_${CI_COMMIT_SHORT_SHA})
#   dest-dir    - Destination directory for extracted cache
#
# Environment variables:
#   CACHE_MANAGER       - Path to cache-manager.sh (required)
#   CI_PIPELINE_ID      - GitLab pipeline ID (for marker file)
#   EXTRACT_TIMEOUT     - Timeout in seconds (default: 300)
#   SKIP_WAIT           - Set to "true" to skip PostgreSQL wait
#   POSTGRES_HOST       - PostgreSQL host for readiness check (default: localhost)
#   POSTGRES_PORT       - PostgreSQL port (default: 5432)
#
# Marker file pattern:
#   ${dest-dir}/.ready - Contains pipeline ID that performed extraction
#
# Exit codes:
#   0 - Success (cache extracted or already available)
#   1 - Error (cache not found, extraction failed, or timeout)

set -euo pipefail

# Arguments
CACHE_TYPE="${1:?Usage: extract-cache-and-wait.sh <cache-type> <cache-key> <dest-dir>}"
CACHE_KEY="${2:?Usage: extract-cache-and-wait.sh <cache-type> <cache-key> <dest-dir>}"
DEST_DIR="${3:?Usage: extract-cache-and-wait.sh <cache-type> <cache-key> <dest-dir>}"

# Configuration
MARKER_FILE="${DEST_DIR}/.ready"
TIMEOUT="${EXTRACT_TIMEOUT:-300}"
POSTGRES_HOST="${POSTGRES_HOST:-localhost}"
POSTGRES_PORT="${POSTGRES_PORT:-5432}"
SKIP_WAIT="${SKIP_WAIT:-false}"

echo "=== HAF Block Explorer Cache Extraction ==="
echo "Cache type: ${CACHE_TYPE}"
echo "Cache key:  ${CACHE_KEY}"
echo "Dest dir:   ${DEST_DIR}"
echo "Pipeline:   ${CI_PIPELINE_ID:-local}"
echo ""

# Verify cache-manager is available
if [[ -z "${CACHE_MANAGER:-}" ]]; then
    echo "ERROR: CACHE_MANAGER environment variable not set"
    echo "Ensure .fetch_cache_manager has been run first"
    exit 1
fi

if [[ ! -x "$CACHE_MANAGER" ]]; then
    echo "ERROR: Cache manager not found or not executable: $CACHE_MANAGER"
    exit 1
fi

# Check if extraction already done for this pipeline
if [[ -f "$MARKER_FILE" ]]; then
    MARKER_PIPELINE=$(cat "$MARKER_FILE" 2>/dev/null || echo "")
    if [[ "$MARKER_PIPELINE" == "${CI_PIPELINE_ID:-local}" ]]; then
        echo "Cache already extracted for this pipeline (marker: ${MARKER_PIPELINE})"
        echo "Skipping extraction"
        exit 0
    fi
    echo "Marker file exists but for different pipeline: ${MARKER_PIPELINE}"
fi

# Check if data directory already has valid data
PGDATA="${DEST_DIR}/datadir/pgdata"
if [[ -d "$PGDATA" ]]; then
    echo "Data directory exists: $PGDATA"
    # Check if PostgreSQL data looks valid
    if [[ -f "$PGDATA/PG_VERSION" ]]; then
        echo "PostgreSQL data appears valid (PG_VERSION exists)"
        # Update marker file
        echo "${CI_PIPELINE_ID:-local}" > "$MARKER_FILE"
        echo "Updated marker file, skipping extraction"
        exit 0
    fi
    echo "PostgreSQL data incomplete, will re-extract"
fi

# Create destination directory
mkdir -p "${DEST_DIR}"

# Extract cache using cache-manager
echo ""
echo "=== Extracting Cache ==="
echo "Running: CACHE_HANDLING=haf \$CACHE_MANAGER get ${CACHE_TYPE} ${CACHE_KEY} ${DEST_DIR}"

if ! CACHE_HANDLING=haf "$CACHE_MANAGER" get "${CACHE_TYPE}" "${CACHE_KEY}" "${DEST_DIR}"; then
    echo ""
    echo "ERROR: Cache extraction failed"
    echo ""
    echo "Possible causes:"
    echo "  - Cache does not exist for key: ${CACHE_KEY}"
    echo "  - NFS not mounted or not accessible"
    echo "  - Sync job did not complete successfully"
    echo ""
    echo "Debug commands:"
    echo "  ls -la ${DATA_CACHE_NFS_PREFIX:-/nfs/ci-cache}/${CACHE_TYPE}/ | head -10"
    echo "  ls -la /nfs/ci-cache/${CACHE_TYPE}/${CACHE_KEY}.tar"
    exit 1
fi

echo "Cache extracted successfully"

# Fix PostgreSQL permissions (must be 700 for pg_ctl to work)
if [[ -d "$PGDATA" ]]; then
    echo ""
    echo "=== Fixing PostgreSQL Permissions ==="
    chmod 700 "$PGDATA"
    echo "Set $PGDATA permissions to 700"
fi

# Write marker file
echo "${CI_PIPELINE_ID:-local}" > "$MARKER_FILE"
echo "Wrote marker file: $MARKER_FILE"

# Optionally wait for PostgreSQL
if [[ "$SKIP_WAIT" == "true" ]]; then
    echo ""
    echo "Skipping PostgreSQL wait (SKIP_WAIT=true)"
    exit 0
fi

echo ""
echo "=== Waiting for PostgreSQL ==="
echo "Host: ${POSTGRES_HOST}:${POSTGRES_PORT}"
echo "Timeout: ${TIMEOUT}s"

WAITED=0
while ! pg_isready -h "${POSTGRES_HOST}" -p "${POSTGRES_PORT}" -q 2>/dev/null; do
    sleep 5
    WAITED=$((WAITED + 5))
    if [[ $WAITED -ge $TIMEOUT ]]; then
        echo ""
        echo "ERROR: PostgreSQL not ready after ${TIMEOUT}s"
        echo "This may be normal if the container hasn't started yet."
        echo "If running in CI, ensure docker-compose is started after this script."
        # Exit 0 here since we extracted successfully - postgres will start later
        exit 0
    fi
    echo "Waiting for PostgreSQL... (${WAITED}s)"
done

echo "PostgreSQL ready after ${WAITED}s"
exit 0
