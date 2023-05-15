#! /bin/bash

# credits: https://gitlab.syncad.com/hive/HAfAH/-/blob/master/scripts/generate_version_sql.bash
# usage: ./generate_version_sql.bash root_project_dir [git_command_prefix = ""]
# example: ./generate_version_sql.bash $PWD sudo
# example: ./generate_version_sql.bash /var/my/sources

set -euo pipefail

path_to_sql_version_file="$1/set_version_in_sql.pgsql"

# acquiring hash without git
GIT_HASH=`$2 git --git-dir="$1/.git" --work-tree="$1" rev-parse HEAD`

echo "TRUNCATE TABLE hafbe_app.version; INSERT INTO hafbe_app.version(git_hash) VALUES ('$GIT_HASH');" > $path_to_sql_version_file