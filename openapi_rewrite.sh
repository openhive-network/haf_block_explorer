#!/bin/bash

set -e
set -o pipefail

SCRIPTDIR="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 || exit 1; pwd -P )"

if [ "$#" -ne 2 ]; then
cat <<EOF
  Script used to search for all SQL scripts with openapi descriptions...

  Usage: $0 <output_directory> <directory1> <directory2>
  
EOF

  # Default directories if none provided
  DEFAULT_DIR1="$SCRIPTDIR/output"
  DEFAULT_DIR2="$SCRIPTDIR/endpoints/"
  DEFAULT_DIR3="$SCRIPTDIR/backend/types"

  echo "Using default HAF block explorer types and endpoints directories $DEFAULT_DIR2 $DEFAULT_DIR1"
fi

# Directories to search for .sql files
OUTPUT_DIR1="${1:-$DEFAULT_DIR1}"
SEARCH_DIR2="${2:-$DEFAULT_DIR2}"
SEARCH_DIR3="${3:-$DEFAULT_DIR3}"

# Find all .sql files in both directories and their subdirectories
find_and_sort_sql_files() {
  local dir="$1"
  local base_dir="$2"
  find "$dir" -type f -name "*.sql" | awk -F/ '{ print NF, $0 }' | sort -n | cut -d' ' -f2- | xargs -I {} realpath --relative-to="$base_dir" "{}"
}

# Find and sort .sql files in each directory separately
SQL_FILES_DIR1=$(find_and_sort_sql_files "$SEARCH_DIR2" "$SCRIPTDIR")
SQL_FILES_DIR2=$(find_and_sort_sql_files "$SEARCH_DIR3" "$SCRIPTDIR")

# Combine the results
SQL_FILES="$SQL_FILES_DIR2 $SQL_FILES_DIR1"

# Run test.py with all the .sql files as arguments

# shellcheck disable=SC2086
python3 process_openapi.py $OUTPUT_DIR1 $SQL_FILES