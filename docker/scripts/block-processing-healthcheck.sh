#! /bin/sh

set -e

# Setup a trap to kill potentially pending healthcheck SQL query at script exit
trap 'trap - 2 15 && kill -- -$$' 2 15

postgres_user=${POSTGRES_USER:-"haf_admin"}
postgres_host=${POSTGRES_HOST:-"localhost"}
postgres_port=${POSTGRES_PORT:-5432}
POSTGRES_ACCESS=${POSTGRES_URL:-"postgresql://$postgres_user@$postgres_host:$postgres_port/haf_block_log?application_name=block_explorer_health_check"}

# this health check will return healthy if:
# - haf_block_explorer has processed a block in the last 60 seconds
#   (as long as it was also after the container started, we don't want
#    to report healthy immediately after a restart)
# or
# - haf_block_explorer's head block has caught up to haf's irreversible block
#   (so we don't mark haf_block_explorer as unhealthy if HAF stops getting blocks)
#
# This check needs to know when the block processing started, so the docker entrypoint
# must write this to a file like:
#   date --utc --iso-8601=seconds > /tmp/block_processing_startup_time.txt
if [ ! -f "/tmp/block_processing_startup_time.txt" ]; then
  echo "file /tmp/block_processing_startup_time.txt does not exist, which means block"
  echo "processing hasn't started yet"
  exit 1
fi
STARTUP_TIME="$(cat /tmp/block_processing_startup_time.txt)"
CHECK="SET TIME ZONE 'UTC'; \
       SELECT ((now() - (SELECT min(last_active_at) FROM hafd.contexts WHERE name in ('hafbe_app', 'hafbe_bal')) < interval '1 minute') \
               AND (SELECT min(last_active_at) FROM hafd.contexts WHERE name in ('hafbe_app', 'hafbe_bal')) > '${STARTUP_TIME}'::timestamp) OR \
              hive.is_app_in_sync(ARRAY['hafbe_app', 'hafbe_bal']);"


# the docker container probably won't have a locale set, do this to suppress the warning
export LC_ALL=C
exec [ "$(psql "$POSTGRES_ACCESS" --quiet --no-align --tuples-only --command="${CHECK}")" = t ]
