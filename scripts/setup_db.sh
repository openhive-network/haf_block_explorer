#!/bin/bash

set -e
set -o pipefail

setup_owner() {
  if ! id $owner_role &>/dev/null; then
    sudo useradd -m $owner_role
    sudo chsh -s /bin/bash $owner_role
  fi;

  sudo -nu $admin_role psql -d $DB_NAME -a -v "ON_ERROR_STOP=on" -f - <<EOF
DO \$$
BEGIN
  CREATE ROLE $owner_role WITH LOGIN NOINHERIT IN ROLE hive_applications_group;
  EXCEPTION WHEN DUPLICATE_OBJECT THEN
  RAISE NOTICE '$owner_role role already exists';
END
\$$;
EOF

  sudo -nu $admin_role psql -d $DB_NAME -a -v "ON_ERROR_STOP=on" -f - <<EOF
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

  result=$(sudo -nu $admin_role psql -d $DB_NAME -a -v "ON_ERROR_STOP=on" -f - <<EOF
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
  #setup hafah 
  sudo -nu $admin_role psql -d $DB_NAME -a -v "ON_ERROR_STOP=on" -f "$hafah_dir/queries/ah_schema_functions.pgsql"
  #setup balance tracker 
  sudo -nu $admin_role psql -d $DB_NAME -a -v "ON_ERROR_STOP=on" -c "do \$\$ BEGIN if hive.app_context_exists('btracker_app') THEN perform hive.app_remove_context('btracker_app'); end if; END \$\$"
  sudo -nu $admin_role psql -d $DB_NAME -a -v "ON_ERROR_STOP=on" -c "CREATE SCHEMA IF NOT EXISTS btracker_app;"
  sudo -nu $admin_role psql -d $DB_NAME -a -v "ON_ERROR_STOP=on" -f "$btracker_dir/api/btracker_api.sql"
  sudo -nu $admin_role psql -d $DB_NAME -a -v "ON_ERROR_STOP=on" -f "$btracker_dir/db/btracker_app.sql"
}

setup_extensions() {
  sudo -nu $admin_role psql -d $DB_NAME -a -v "ON_ERROR_STOP=on" -c "CREATE EXTENSION IF NOT EXISTS plpython3u SCHEMA pg_catalog;"
  sudo -nu $admin_role psql -d $DB_NAME -a -v "ON_ERROR_STOP=on" -c "UPDATE pg_language SET lanpltrusted = true WHERE lanname = 'plpython3u';"
}

setup_api() {
  # setup db schema
  sudo -nu $owner_role psql -d $DB_NAME -a -v "ON_ERROR_STOP=on" -f $db_dir/database_schema.sql 
  sudo -nu $owner_role psql -d $DB_NAME -a -v "ON_ERROR_STOP=on" -f $db_dir/hafbe_app_helpers.sql
  sudo -nu $owner_role psql -d $DB_NAME -a -v "ON_ERROR_STOP=on" -f $db_dir/hafbe_app_indexes.sql
  sudo -nu $owner_role psql -d $DB_NAME -a -v "ON_ERROR_STOP=on" -f $db_dir/main_loop.sql
  sudo -nu $owner_role psql -d $DB_NAME -a -v "ON_ERROR_STOP=on" -f $db_dir/massive_processing.sql
  sudo -nu $owner_role psql -d $DB_NAME -a -v "ON_ERROR_STOP=on" -f $db_dir/process_block_range.sql

  
  # must be done by admin because of hive.contexts permissions
  sudo -nu $admin_role psql -d $DB_NAME -a -v "ON_ERROR_STOP=on" -c "CALL hafbe_app.create_context_if_not_exists('btracker_app');"
  sudo -nu $owner_role psql -d $DB_NAME -a -v "ON_ERROR_STOP=on" -c "CALL hafbe_app.create_context_if_not_exists('hafbe_app');"

  sudo -nu $admin_role psql -d $DB_NAME -a -v "ON_ERROR_STOP=on" -c "SELECT btracker_app.define_schema();"
  sudo -nu $owner_role psql -d $DB_NAME -a -v "ON_ERROR_STOP=on" -c "SELECT hafbe_app.define_schema();"

  sudo -nu $admin_role psql -d $DB_NAME -a -v "ON_ERROR_STOP=on" -c "GRANT ALL ON TABLE hafbe_app.app_status TO $owner_role;"

  # setup backend schema
  sudo -nu $owner_role psql -d $DB_NAME -a -v "ON_ERROR_STOP=on" -f $backend/backend_schema.sql
  sudo -nu $owner_role psql -d $DB_NAME -a -v "ON_ERROR_STOP=on" -f $backend/hafbe_exceptions.sql
  sudo -nu $owner_role psql -d $DB_NAME -a -v "ON_ERROR_STOP=on" -f $backend/hafbe_types.sql
  sudo -nu $owner_role psql -d $DB_NAME -a -v "ON_ERROR_STOP=on" -f $backend/hafbe_views.sql
  sudo -nu $owner_role psql -d $DB_NAME -a -v "ON_ERROR_STOP=on" -f $backend/get_account_data.sql
  sudo -nu $owner_role psql -d $DB_NAME -a -v "ON_ERROR_STOP=on" -f $backend/get_block_stats.sql
  sudo -nu $owner_role psql -d $DB_NAME -a -v "ON_ERROR_STOP=on" -f $backend/get_operation_types.sql
  sudo -nu $owner_role psql -d $DB_NAME -a -v "ON_ERROR_STOP=on" -f $backend/get_operations.sql
  sudo -nu $owner_role psql -d $DB_NAME -a -v "ON_ERROR_STOP=on" -f $backend/get_transactions.sql
  sudo -nu $owner_role psql -d $DB_NAME -a -v "ON_ERROR_STOP=on" -f $backend/get_witness_data.sql

  # setup endpoints schema
  sudo -nu $owner_role psql -d $DB_NAME -a -v "ON_ERROR_STOP=on" -f $endpoints/endpoints_schema.sql 
  sudo -nu $owner_role psql -d $DB_NAME -a -v "ON_ERROR_STOP=on" -f $endpoints/get_account.sql 
  sudo -nu $owner_role psql -d $DB_NAME -a -v "ON_ERROR_STOP=on" -f $endpoints/get_block.sql 
  sudo -nu $owner_role psql -d $DB_NAME -a -v "ON_ERROR_STOP=on" -f $endpoints/get_input_type.sql 
  sudo -nu $owner_role psql -d $DB_NAME -a -v "ON_ERROR_STOP=on" -f $endpoints/get_operation_type.sql 
  sudo -nu $owner_role psql -d $DB_NAME -a -v "ON_ERROR_STOP=on" -f $endpoints/get_transaction.sql 
  sudo -nu $owner_role psql -d $DB_NAME -a -v "ON_ERROR_STOP=on" -f $endpoints/get_witness.sql 

  # must be done by admin
  sudo -nu $admin_role psql -d $DB_NAME -a -v "ON_ERROR_STOP=on" -f $backend/hafbe_roles.sql
}

create_haf_indexes() {
  echo "Creating indexes, this might take a while."
  sudo -nu $admin_role psql -d $DB_NAME -a -v "ON_ERROR_STOP=on" -c "\timing" -c "SELECT hafbe_indexes.create_haf_indexes();"
}

DB_NAME=haf_block_log
admin_role=haf_admin
owner_role=hafbe_owner


endpoints=$PWD/endpoints
backend=$PWD/backend
db_dir=$PWD/database
hafah_dir=$PWD/submodules/hafah
btracker_dir=$PWD/submodules/btracker
sudo echo

if [ "$1" = "all" ]; then
  setup_owner
  setup_apps
  setup_extensions
  setup_api
  create_haf_indexes
elif [ "$1" = "owner" ]; then
  setup_owner
elif [ "$1" = "apps" ]; then
  setup_apps
elif [ "$1" = "extensions" ]; then
  setup_extensions
elif [ "$1" = "api" ]; then
  setup_api
elif [ "$1" =  "haf-indexes" ]; then
  create_haf_indexes
else
  echo "job not found"
  exit 1
fi;
