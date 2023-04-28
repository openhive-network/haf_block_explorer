#!/bin/bash

set -e
set -o pipefail

POSTGRES_HOST="localhost"
POSTGRES_PORT=5432
POSTGRES_USER="haf_admin"
COMMAND=""

print_help () {
    echo "Usage: $0 [OPTION[=VALUE]]..."
    echo
    echo "Allows to setup a database already filled by HAF instance, to work with haf_be application."
    echo "OPTIONS:"
    echo "  --host=VALUE             Allows to specify a PostgreSQL host location (defaults to localhost)"
    echo "  --port=NUMBER            Allows to specify a PostgreSQL operating port (defaults to 5432)"
    echo "  --user=VALUE             Allows to specify a PostgreSQL user (defaults to haf_admin)"
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
    --help)
        print_help
        exit 0
        ;;
    -*)
        echo "ERROR: '$1' is not a valid option"
        echo
        print_help
        exit 1
        ;;
    *)
        echo "ERROR: '$1' is not a valid argument"
        echo
        print_help
        exit 2
        ;;
    esac
    shift
done

POSTGRES_ACCESS_ADMIN="postgresql://$POSTGRES_USER@$POSTGRES_HOST:$POSTGRES_PORT/haf_block_log"

POSTGRES_ACCESS_OWNER="postgresql://$owner_role@$POSTGRES_HOST:$POSTGRES_PORT/haf_block_log"

setup_owner() {
  if ! id $owner_role &>/dev/null; then
    sudo useradd -m $owner_role
    sudo chsh -s /bin/bash $owner_role
  fi;

psql $POSTGRES_ACCESS_ADMIN -v "ON_ERROR_STOP=on" -f - <<EOF
DO \$$
BEGIN
  CREATE ROLE $owner_role WITH LOGIN NOINHERIT IN ROLE hive_applications_group;
  EXCEPTION WHEN DUPLICATE_OBJECT THEN
  RAISE NOTICE '$owner_role role already exists';
END
\$$;
EOF

psql $POSTGRES_ACCESS_ADMIN -v "ON_ERROR_STOP=on" -f - <<EOF
DO \$$
BEGIN
  GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $owner_role;
  GRANT USAGE ON SCHEMA hive TO $owner_role;
  GRANT CREATE ON SCHEMA hive TO $owner_role;
  GRANT SELECT ON ALL TABLES IN SCHEMA hive TO $owner_role;
  GRANT ALL ON ALL SEQUENCES IN SCHEMA hive TO $owner_role;
  GRANT ALL ON ALL FUNCTIONS IN SCHEMA hive TO $owner_role;
  GRANT ALL ON TABLE hive.contexts TO $owner_role;
  GRANT ALL ON TABLE hive.registered_tables TO $owner_role;
  GRANT ALL ON TABLE hive.triggers TO $owner_role;
END
\$$;
EOF
}

find_function() {
  schema=$1
  function=$2

  result=$(psql $POSTGRES_ACCESS_ADMIN -v "ON_ERROR_STOP=on" -f - <<EOF
DO \$$
BEGIN
  IF (SELECT COUNT(1)
    FROM pg_catalog.pg_namespace n
    JOIN pg_catalog.pg_proc p ON p.pronamespace = n.oid
    WHERE n.nspname = '$schema' AND p.proname = '$function') = 0
  THEN
    RAISE NOTICE '$schema.$function() does not exist';
  END IF;
END
\$$;
EOF
)
}

setup_apps() {
  cd $hafah_dir && bash $hafah_dir/scripts/setup_postgres.sh --postgres-url=$POSTGRES_ACCESS_ADMIN
  cd $hafah_dir && bash $hafah_dir/scripts/generate_version_sql.bash $PWD "sudo --user=$POSTGRES_USER"
  cd $hafah_dir && bash $hafah_dir/scripts/setup_db.sh --postgres-url=$POSTGRES_ACCESS_ADMIN

  cd $btracker_dir && bash $btracker_dir/scripts/setup_db.sh --postgres-url=$POSTGRES_ACCESS_ADMIN --no-context=$context
}

setup_extensions() {
  psql $POSTGRES_ACCESS_ADMIN -v "ON_ERROR_STOP=on" -c "CREATE EXTENSION IF NOT EXISTS plpython3u SCHEMA pg_catalog;"
  psql $POSTGRES_ACCESS_ADMIN -v "ON_ERROR_STOP=on" -c "UPDATE pg_language SET lanpltrusted = true WHERE lanname = 'plpython3u';"
}

setup_api() {
  # setup db schema
  psql $POSTGRES_ACCESS_OWNER -v "ON_ERROR_STOP=on" -f $db_dir/database_schema.sql 
  psql $POSTGRES_ACCESS_OWNER -v "ON_ERROR_STOP=on" -f $db_dir/hafbe_app_helpers.sql
  psql $POSTGRES_ACCESS_OWNER -v "ON_ERROR_STOP=on" -f $db_dir/hafbe_app_indexes.sql
  psql $POSTGRES_ACCESS_OWNER -v "ON_ERROR_STOP=on" -f $db_dir/main_loop.sql
  psql $POSTGRES_ACCESS_OWNER -v "ON_ERROR_STOP=on" -f $db_dir/massive_processing.sql
  psql $POSTGRES_ACCESS_OWNER -v "ON_ERROR_STOP=on" -f $db_dir/process_block_range.sql

  
  # must be done by admin because of hive.contexts permissions
  psql $POSTGRES_ACCESS_OWNER -v "ON_ERROR_STOP=on" -c "CALL hafbe_app.create_context_if_not_exists('hafbe_app');"

  psql $POSTGRES_ACCESS_OWNER -v "ON_ERROR_STOP=on" -c "SELECT hafbe_app.define_schema();"
  psql $POSTGRES_ACCESS_ADMIN -v "ON_ERROR_STOP=on" -c "SELECT btracker_app.define_schema();"



  psql $POSTGRES_ACCESS_ADMIN -v "ON_ERROR_STOP=on" -c "GRANT ALL ON TABLE hafbe_app.app_status TO $owner_role;"

  # setup backend schema
  psql $POSTGRES_ACCESS_OWNER -v "ON_ERROR_STOP=on" -f $backend/backend_schema.sql
  psql $POSTGRES_ACCESS_OWNER -v "ON_ERROR_STOP=on" -f $backend/hafbe_exceptions.sql
  psql $POSTGRES_ACCESS_OWNER -v "ON_ERROR_STOP=on" -f $backend/hafbe_types.sql
  psql $POSTGRES_ACCESS_OWNER -v "ON_ERROR_STOP=on" -f $backend/hafbe_views.sql
  psql $POSTGRES_ACCESS_OWNER -v "ON_ERROR_STOP=on" -f $backend/get_account_data.sql
  psql $POSTGRES_ACCESS_OWNER -v "ON_ERROR_STOP=on" -f $backend/get_block_stats.sql
  psql $POSTGRES_ACCESS_OWNER -v "ON_ERROR_STOP=on" -f $backend/get_operation_types.sql
  psql $POSTGRES_ACCESS_OWNER -v "ON_ERROR_STOP=on" -f $backend/get_operations.sql
  psql $POSTGRES_ACCESS_OWNER -v "ON_ERROR_STOP=on" -f $backend/get_transactions.sql
  psql $POSTGRES_ACCESS_OWNER -v "ON_ERROR_STOP=on" -f $backend/get_witness_data.sql

  # setup endpoints schema
  psql $POSTGRES_ACCESS_OWNER -v "ON_ERROR_STOP=on" -f $endpoints/endpoints_schema.sql 
  psql $POSTGRES_ACCESS_OWNER -v "ON_ERROR_STOP=on" -f $endpoints/get_account.sql 
  psql $POSTGRES_ACCESS_OWNER -v "ON_ERROR_STOP=on" -f $endpoints/get_block.sql 
  psql $POSTGRES_ACCESS_OWNER -v "ON_ERROR_STOP=on" -f $endpoints/get_input_type.sql 
  psql $POSTGRES_ACCESS_OWNER -v "ON_ERROR_STOP=on" -f $endpoints/get_operation_type.sql
  psql $POSTGRES_ACCESS_OWNER -v "ON_ERROR_STOP=on" -f $endpoints/get_operations.sql
  psql $POSTGRES_ACCESS_OWNER -v "ON_ERROR_STOP=on" -f $endpoints/get_transaction.sql 
  psql $POSTGRES_ACCESS_OWNER -v "ON_ERROR_STOP=on" -f $endpoints/get_witness.sql 

  # must be done by admin
  psql $POSTGRES_ACCESS_ADMIN -v "ON_ERROR_STOP=on" -f $backend/hafbe_roles.sql
}

create_haf_indexes() {
  echo "Creating indexes, this might take a while."
  psql $POSTGRES_ACCESS_ADMIN -v "ON_ERROR_STOP=on" -c "\timing" -c "SELECT hafbe_indexes.create_haf_indexes();"
}

context="no"
DB_NAME=haf_block_log
owner_role=hafbe_owner

endpoints=$PWD/../endpoints
backend=$PWD/../backend
db_dir=$PWD/../database
hafah_dir=$PWD/../submodules/hafah
btracker_dir=$PWD/../submodules/btracker

  setup_owner
  setup_apps
  setup_extensions
  setup_api
  create_haf_indexes