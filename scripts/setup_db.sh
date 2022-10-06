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

setup_extensions() {
  sudo -nu $admin_role psql -d $DB_NAME -a -v "ON_ERROR_STOP=on" -c "CREATE EXTENSION IF NOT EXISTS plpython3u SCHEMA pg_catalog;"
  sudo -nu $admin_role psql -d $DB_NAME -a -v "ON_ERROR_STOP=on" -c "UPDATE pg_language SET lanpltrusted = true WHERE lanname = 'plpython3u';"
}

setup_api() {
  sudo -nu $owner_role psql -d $DB_NAME -a -v "ON_ERROR_STOP=on" -f $db_dir/hafbe_app.sql
  
  sudo -nu $owner_role psql -d $DB_NAME -a -v "ON_ERROR_STOP=on" -f $db_dir/indexes.sql
  # must be done by admin because of hive.contexts permissions
  sudo -nu $owner_role psql -d $DB_NAME -a -v "ON_ERROR_STOP=on" -c "CALL hafbe_app.create_context_if_not_exists('hafbe_app');"
  sudo -nu $admin_role psql -d $DB_NAME -a -v "ON_ERROR_STOP=on" -c "GRANT ALL ON TABLE hafbe_app.app_status TO $owner_role;"

  sudo -nu $owner_role psql -d $DB_NAME -a -v "ON_ERROR_STOP=on" -f $postgrest_dir/views.sql
  sudo -nu $owner_role psql -d $DB_NAME -a -v "ON_ERROR_STOP=on" -f $postgrest_dir/types.sql
  sudo -nu $owner_role psql -d $DB_NAME -a -v "ON_ERROR_STOP=on" -f $postgrest_dir/exceptions.sql
  sudo -nu $owner_role psql -d $DB_NAME -a -v "ON_ERROR_STOP=on" -f $postgrest_dir/backend.sql
  sudo -nu $owner_role psql -d $DB_NAME -a -v "ON_ERROR_STOP=on" -f $postgrest_dir/endpoints.sql
  # must be done by admin
  sudo -nu $admin_role psql -d $DB_NAME -a -v "ON_ERROR_STOP=on" -f $postgrest_dir/roles.sql
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

if [ "$1" = "setup-role" ]; then
  setup_owner
elif [ "$1" = "setup-extensions" ]; then
  setup_extensions
elif [ "$1" = "setup-api" ]; then
  setup_api
elif [ "$1" = "setup-permissions" ]; then
  setup_permissions
elif [ "$1" =  "create-haf-indexes" ]; then
  create_haf_indexes
else
  setup_owner
  setup_extensions
  setup_api
  create_haf_indexes
fi;