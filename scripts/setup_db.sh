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
  build_dir=$PWD/build
  rm -rf $build_dir
  mkdir $build_dir

  # hafah
  schema="hafah_python"
  function="get_transaction_json"

  result=$(find_function $schema $function 2>&1)
  notice="$schema.$function() does not exist"

  if [[ $result = *"$notice"* ]]; then
    cd $build_dir
    git clone git@gitlab.syncad.com:hive/HAfAH.git
    cd $build_dir/HAfAH
    git checkout develop
    
    sudo -nu $admin_role psql -d $DB_NAME -a -v "ON_ERROR_STOP=on" -f "queries/ah_schema_functions.pgsql"
  fi

  # btracker
  schema="btracker_app"
  function="find_matching_accounts"

  result=$(find_function $schema $function 2>&1)
  notice="$schema.$function() does not exist"

  if [[ $result = *"$notice"* ]]; then
    cd $build_dir
    git clone git@gitlab.syncad.com:hive/balance_tracker.git
    cd $build_dir/balance_tracker
    git checkout develop
    sudo -nu $admin_role psql -d $DB_NAME -a -v "ON_ERROR_STOP=on" -c "do \$\$ BEGIN if hive.app_context_exists('btracker_app') THEN perform hive.app_remove_context('btracker_app'); end if; END \$\$"
    sudo -nu $admin_role psql -d $DB_NAME -a -v "ON_ERROR_STOP=on" -c "CREATE SCHEMA IF NOT EXISTS btracker_app;"
    sudo -nu $admin_role psql -d $DB_NAME -a -v "ON_ERROR_STOP=on" -f "api/btracker_api.sql"
    sudo -nu $admin_role psql -d $DB_NAME -a -v "ON_ERROR_STOP=on" -f "db/btracker_app.sql"
  fi
}

setup_extensions() {
  sudo -nu $admin_role psql -d $DB_NAME -a -v "ON_ERROR_STOP=on" -c "CREATE EXTENSION IF NOT EXISTS plpython3u SCHEMA pg_catalog;"
  sudo -nu $admin_role psql -d $DB_NAME -a -v "ON_ERROR_STOP=on" -c "UPDATE pg_language SET lanpltrusted = true WHERE lanname = 'plpython3u';"
}

setup_api() {
  sudo -nu $owner_role psql -d $DB_NAME -a -v "ON_ERROR_STOP=on" -f $db_dir/hafbe_app.sql
  
  sudo -nu $owner_role psql -d $DB_NAME -a -v "ON_ERROR_STOP=on" -f $db_dir/indexes.sql
  # must be done by admin because of hive.contexts permissions
  sudo -nu $admin_role psql -d $DB_NAME -a -v "ON_ERROR_STOP=on" -c "CALL hafbe_app.create_context_if_not_exists('btracker_app');"
  sudo -nu $owner_role psql -d $DB_NAME -a -v "ON_ERROR_STOP=on" -c "CALL hafbe_app.create_context_if_not_exists('hafbe_app');"

  sudo -nu $admin_role psql -d $DB_NAME -a -v "ON_ERROR_STOP=on" -c "SELECT btracker_app.define_schema();"
  sudo -nu $owner_role psql -d $DB_NAME -a -v "ON_ERROR_STOP=on" -c "SELECT hafbe_app.define_schema();"

  sudo -nu $admin_role psql -d $DB_NAME -a -v "ON_ERROR_STOP=on" -c "GRANT ALL ON TABLE hafbe_app.app_status TO $owner_role;"

  sudo -nu $owner_role psql -d $DB_NAME -a -v "ON_ERROR_STOP=on" -f $postgrest_dir/views.sql
  sudo -nu $owner_role psql -d $DB_NAME -a -v "ON_ERROR_STOP=on" -f $postgrest_dir/types.sql
  sudo -nu $owner_role psql -d $DB_NAME -a -v "ON_ERROR_STOP=on" -f $postgrest_dir/exceptions.sql
  sudo -nu $owner_role psql -d $DB_NAME -a -v "ON_ERROR_STOP=on" -f $postgrest_dir/backend.sql
  sudo -nu $owner_role psql -d $DB_NAME -a -v "ON_ERROR_STOP=on" -f $postgrest_dir/endpoints.sql
  # must be done by admin
  sudo -nu $admin_role psql -d $DB_NAME -a -v "ON_ERROR_STOP=on" -f $postgrest_dir/roles.sql
}

create_indexes() {
  sudo -nu $admin_role psql -d $DB_NAME -a -v "ON_ERROR_STOP=on" -c "call btracker_app.create_indexes();"
}

create_haf_indexes() {
  echo "Creating indexes, this might take a while."
  sudo -nu $admin_role psql -d $DB_NAME -a -v "ON_ERROR_STOP=on" -c "\timing" -c "SELECT hafbe_indexes.create_haf_indexes();"
}

DB_NAME=haf_block_log
admin_role=haf_admin
owner_role=hafbe_owner

postgrest_dir=$PWD/api
db_dir=$PWD/db

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