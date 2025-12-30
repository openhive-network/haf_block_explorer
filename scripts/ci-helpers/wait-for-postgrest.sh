#!/bin/bash
# Wait for HAF and PostgREST to be ready in docker-compose test environment.
#
# This script waits for both services to be healthy before tests can run:
# 1. HAF (PostgreSQL) - database must be accepting connections
# 2. PostgREST - REST API must be responding
#
# Usage:
#   wait-for-postgrest.sh [options]
#
# Environment variables:
#   HAF_HOST            - HAF/PostgreSQL hostname (default: haf)
#   HAF_PORT            - PostgreSQL port (default: 5432)
#   POSTGREST_HOST      - PostgREST hostname (default: postgrest)
#   POSTGREST_PORT      - PostgREST port (default: 3000)
#   POSTGREST_ADMIN_PORT - PostgREST admin port (default: 3001)
#   WAIT_TIMEOUT        - Total timeout in seconds (default: 300)

set -euo pipefail

HAF_HOST="${HAF_HOST:-haf}"
HAF_PORT="${HAF_PORT:-5432}"
POSTGREST_HOST="${POSTGREST_HOST:-postgrest}"
POSTGREST_PORT="${POSTGREST_PORT:-3000}"
POSTGREST_ADMIN_PORT="${POSTGREST_ADMIN_PORT:-3001}"
TIMEOUT="${WAIT_TIMEOUT:-300}"

echo "=== Waiting for Test Services ==="
echo "HAF:      ${HAF_HOST}:${HAF_PORT}"
echo "PostgREST: ${POSTGREST_HOST}:${POSTGREST_PORT} (admin: ${POSTGREST_ADMIN_PORT})"
echo "Timeout:  ${TIMEOUT}s"
echo ""

WAITED=0

# Wait for HAF/PostgreSQL
echo "--- Waiting for HAF (PostgreSQL) ---"
while ! pg_isready -h "${HAF_HOST}" -p "${HAF_PORT}" -q 2>/dev/null; do
    sleep 5
    WAITED=$((WAITED + 5))
    if [[ $WAITED -ge $TIMEOUT ]]; then
        echo "ERROR: HAF not ready after ${TIMEOUT}s"
        exit 1
    fi
    echo "Waiting for HAF... (${WAITED}s)"
done
echo "HAF ready after ${WAITED}s"
echo ""

# Wait for PostgREST
echo "--- Waiting for PostgREST ---"
while ! curl -sf "http://${POSTGREST_HOST}:${POSTGREST_ADMIN_PORT}/ready" >/dev/null 2>&1; do
    sleep 5
    WAITED=$((WAITED + 5))
    if [[ $WAITED -ge $TIMEOUT ]]; then
        echo "ERROR: PostgREST not ready after ${TIMEOUT}s"
        echo ""
        echo "Debug info:"
        echo "  curl -v http://${POSTGREST_HOST}:${POSTGREST_ADMIN_PORT}/ready"
        echo "  docker compose logs postgrest"
        exit 1
    fi
    echo "Waiting for PostgREST... (${WAITED}s)"
done
echo "PostgREST ready after ${WAITED}s"
echo ""

# Verify API is responding
echo "--- Verifying API ---"
if curl -sf "http://${POSTGREST_HOST}:${POSTGREST_PORT}/" >/dev/null 2>&1; then
    echo "API responding at http://${POSTGREST_HOST}:${POSTGREST_PORT}/"
else
    echo "WARNING: API root not responding, but admin endpoint is ready"
fi

echo ""
echo "=== All Services Ready ==="
exit 0
