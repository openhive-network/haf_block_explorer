#! /bin/sh
set -e
cd /haf_block_explorer/scripts

if [ "$1" = "setup_db" ]; then
  shift
  exec ./setup_db.sh --host="${POSTGRES_HOST}" --port="${POSTGRES_PORT:-5432}" --only-hafbe "$@"
elif [ "$1" = "process_blocks" ]; then
  shift
  exec ./process_blocks.sh --host="${POSTGRES_HOST}" --port="${POSTGRES_PORT:-5432}" --user="${POSTGRES_USER:-hafbe_owner}" "$@"
elif [ "$1" = "drop_db" ]; then
  shift
  exec ./drop_db.sh --host="${POSTGRES_HOST}" --port="${POSTGRES_PORT:-5432}" --user="${POSTGRES_USER:-haf_app_admin}" "$@"
else
  echo "usage: $0 setup_db|process_blocks|drop_db"
  exit 1
fi

