#!/bin/bash

set -e
set -o pipefail

print_help () {
cat <<EOF 
    Usage: $0 [OPTION[=VALUE]]...

    Runs performance tests.
    OPTIONS:
    --postgresql-host=HOST           PostgreSQL host (defaults to localhost)
    --postgresql-port=PORT           PostgreSQL port (defaults to 5432)
    --postgresql-user=USER           PostgreSQL user (defaults to haf_admin)
    --postgresql-password=PASSWORD   PostgreSQL password (empty by default)
    --postgresql-database=NAME       PostgreSQL database (defaults to haf_block_log)
    --database-size=NUMBER           Database size to generate (defaults to 1000)
    --postgrest-host=HOST            PostgREST host (defaults to localhost)
    --postgrest-port=PORT            PostgREST port (defaults to 3000)
    --test-thread-count=NUMBER       Number of threads to use to run tests (defaults to 8)
    --test-loop-count=NUMBER         Number of test loops (defaults to 60)
EOF
}

POSTGRESQL_HOST=${POSTGRESQL_HOST:-"localhost"}
POSTGRESQL_PORT=${POSTGRESQL_PORT:-"5432"}
POSTGRESQL_USER=${POSTGRESQL_USER:-"haf_admin"}
POSTGRESQL_PASSWORD=${POSTGRESQL_PASSWORD:-""}
POSTGRESQL_DATABASE=${POSTGRESQL_DATABASE:-"haf_block_log"}
DATABASE_SIZE=${DATABASE_SIZE:-"1000"}
POSTGREST_HOST=${POSTGREST_HOST:-"localhost"}
POSTGREST_PORT=${POSTGREST_PORT:-"3000"}
TEST_THREAD_COUNT=${TEST_THREAD_COUNT:-"8"}
TEST_LOOP_COUNT=${TEST_LOOP_COUNT:-"60"}
TEST_ROOT_DIRECTORY="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"

while [ $# -gt 0 ]; do
  case "$1" in
    --postgresql-host=*)
        POSTGRESQL_HOST="${1#*=}"
        ;;
    --postgresql-port=*)
        POSTGRESQL_PORT="${1#*=}"
        ;;
    --postgresql-user=*)
        POSTGRESQL_USER="${1#*=}"
        ;;
    --postgresql-password=*)
        POSTGRESQL_PASSWORD="${1#*=}"
        ;;
    --postgresql-database=*)
        POSTGRESQL_DATABASE="${1#*=}"
        ;;
    --database-size=*)
        DATABASE_SIZE="${1#*=}"
        ;; 
    --postgrest-host=*)
        POSTGREST_HOST="${1#*=}"
        ;;
    --postgrest-port=*)
        POSTGREST_PORT="${1#*=}"
        ;;
    --test-thread-count=*)
        TEST_THREAD_COUNT="${1#*=}"
        ;;
    --test-loop-count=*)
        TEST_LOOP_COUNT="${1#*=}"
        ;;
    --help|-h|-?)
        print_help
        exit 0
        ;;
    -*)
        echo -e "ERROR: '$1' is not a valid option\n"
        print_help
        exit 1
        ;;
    *)
        echo -e "ERROR: '$1' is not a valid argument\n"
        print_help
        exit 2
        ;;
    esac
    shift
done

cleanup() {
  local result_dir="$TEST_ROOT_DIRECTORY/performance/result"
  local result_report_dir="$result_dir/result_report"

  if [[ -z "${CI:-}" ]]; then
    echo "This will delete previous test result!"
    echo "Press ENTER to continue, ^C to cancel."
    read -r _
  fi
  
  rm -rf "$result_dir"
  mkdir "$result_dir"
  mkdir "$result_report_dir"
}

generate_db() {
  local port="$1"
  local host="$2"
  local user="$3"
  local password="$4"
  local database="$5"
  local database_size="$6"
  python3 "$TEST_ROOT_DIRECTORY/performance/generate_db.py" \
    --port "$port" \
    --host "$host" \
    --user "$user" \
    --password "$password" \
    --database "$database" \
    --database-size "$database_size" #--debug
}

run_jmeter() {
  local port="$1"
  local host="$2"
  local thread_count="$3"
  local loop_count="$4"
  local performance_dir="$TEST_ROOT_DIRECTORY/performance"
  local result_dir="$TEST_ROOT_DIRECTORY/performance/result"
  local result_report_dir="$result_dir/result_report"
  local performance_data_dir="$TEST_ROOT_DIRECTORY/performance/result"
  local jmx_file="$performance_dir/endpoints.jmx"
  local jtl_path="$result_dir/report.jtl"

  jmeter \
        --nongui \
        --testfile "$jmx_file" \
        --logfile "$jtl_path" \
        --reportatendofloadtests \
        --reportoutputfolder "$result_report_dir" \
        --jmeterproperty "backend.port=$port" \
        --jmeterproperty "backend.host=$host" \
        --jmeterproperty "thread.count=$thread_count" \
        --jmeterproperty "loop.count=$loop_count" \
        --jmeterproperty "performance.data.directory=$performance_data_dir" \
        --jmeterproperty "summary.report.path=$result_dir/result.xml"
}

postgres_access="postgresql://$POSTGRESQL_USER@$POSTGRESQL_HOST:$POSTGRESQL_PORT/haf_block_log"

psql "$postgres_access" -v "ON_ERROR_STOP=on" -f "$TEST_ROOT_DIRECTORY/../backend/hafbe_blocksearch_indexes.sql"
psql "$postgres_access" -v "ON_ERROR_STOP=on" -c "UPDATE hafbe_app.app_status SET blocksearch_indexes = TRUE;"

cleanup
generate_db "$POSTGRESQL_PORT" "$POSTGRESQL_HOST" "$POSTGRESQL_USER" "$POSTGRESQL_PASSWORD" "$POSTGRESQL_DATABASE" "$DATABASE_SIZE"
run_jmeter "$POSTGREST_PORT" "$POSTGREST_HOST" "$TEST_THREAD_COUNT" "$TEST_LOOP_COUNT"
