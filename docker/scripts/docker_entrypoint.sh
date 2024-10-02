#! /bin/sh
set -e
cd /home/haf_admin/haf_block_explorer/scripts

if [ "$1" = "install_app" ]; then
  shift
  exec ./install_app.sh --host="${POSTGRES_HOST}" --port="${POSTGRES_PORT:-5432}" --only-hafbe --blocksearch-indexes=true "$@"
elif [ "$1" = "process_blocks" ]; then
  shift
  exec ./process_blocks.sh --host="${POSTGRES_HOST}" --port="${POSTGRES_PORT:-5432}" --user="${POSTGRES_USER:-hafbe_owner}" "$@"
elif [ "$1" = "uninstall_app" ]; then
  shift
  exec ./uninstall_app.sh --host="${POSTGRES_HOST}" --port="${POSTGRES_PORT:-5432}" --user="${POSTGRES_USER:-haf_admin}" "$@"
elif [ "$1" = "start_postgrest" ]; then
  shift
  exec ../scripts/start_postgrest.sh --host="${POSTGRES_HOST}" --port="${POSTGRES_PORT:-5432}"  "$@"
else
  echo "usage: $0 install_app|process_blocks|uninstall_app|start_postgrest"
  exit 1
fi

