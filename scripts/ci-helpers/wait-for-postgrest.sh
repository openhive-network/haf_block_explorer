#!/bin/bash
# Wait for HAF and PostgREST to be ready in docker-compose test environment.
#
# This script waits for both services to be healthy before tests can run:
# 1. HAF (PostgreSQL) - database must be accepting connections
# 2. PostgREST - REST API must be responding
#
# In DinD (Docker-in-Docker) environments:
# - HAF check uses 'docker-compose exec' to run pg_isready inside the container
# - PostgREST check uses 'docker' hostname (the dind service host)
#
# Environment variables:
#   COMPOSE_FILE        - Docker compose file path (required)
#   POSTGREST_HOST      - Host for PostgREST HTTP checks (default: docker)
#   POSTGREST_PORT      - PostgREST port (default: 3000)
#   WAIT_TIMEOUT        - Total timeout in seconds (default: 300)

set -euo pipefail

# Configuration
COMPOSE_FILE="${COMPOSE_FILE:?COMPOSE_FILE must be set}"
POSTGREST_HOST="${POSTGREST_HOST:-docker}"
POSTGREST_PORT="${POSTGREST_PORT:-3000}"
TIMEOUT="${WAIT_TIMEOUT:-300}"

echo "=== Waiting for Test Services ==="
echo "Compose file: ${COMPOSE_FILE}"
echo "PostgREST:    http://${POSTGREST_HOST}:${POSTGREST_PORT}"
echo "Timeout:      ${TIMEOUT}s"
echo ""

WAITED=0

# Wait for HAF/PostgreSQL using docker-compose exec
echo "--- Waiting for HAF (PostgreSQL) ---"
while ! docker-compose -f "${COMPOSE_FILE}" exec -T haf pg_isready -U haf_admin -d haf_block_log 2>/dev/null; do
    sleep 5
    WAITED=$((WAITED + 5))
    if [[ $WAITED -ge $TIMEOUT ]]; then
        echo "ERROR: HAF not ready after ${TIMEOUT}s"
        echo ""
        echo "Container logs:"
        docker-compose -f "${COMPOSE_FILE}" logs haf | tail -50
        exit 1
    fi
    echo "Waiting for HAF... (${WAITED}s)"
done
echo "HAF ready after ${WAITED}s"
echo ""

# Wait for PostgREST - in DinD, exposed ports are available at 'docker' host
echo "--- Waiting for PostgREST ---"
while ! curl -sf --connect-timeout 5 "http://${POSTGREST_HOST}:${POSTGREST_PORT}/" >/dev/null 2>&1; do
    sleep 5
    WAITED=$((WAITED + 5))
    if [[ $WAITED -ge $TIMEOUT ]]; then
        echo "ERROR: PostgREST not ready after ${TIMEOUT}s"
        echo ""
        echo "Container logs:"
        docker-compose -f "${COMPOSE_FILE}" logs postgrest | tail -50
        exit 1
    fi
    echo "Waiting for PostgREST... (${WAITED}s)"
done
echo "PostgREST ready after ${WAITED}s"
echo ""

echo "=== All Services Ready ==="
exit 0
