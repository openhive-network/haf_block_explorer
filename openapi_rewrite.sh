#!/bin/bash

set -e
set -o pipefail

SCRIPTDIR="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 || exit 1; pwd -P )"
types_dir="backend/types/"
endpoints_dir="endpoints/"

cat <<EOF
  Script used to search for all SQL scripts with openapi descriptions...

  Usage: $0 <output_directory> <type_directories> <endpoint_directories>
  
EOF

# Default directories with fixed order if none provided
DEFAULT_OUTPUT="$SCRIPTDIR/output"
DEFAULT_TYPES="
$types_dir/backend_types.sql

$types_dir/witnesses/witness.sql
$types_dir/witnesses/witness_voters.sql
$types_dir/witnesses/witness_votes_history_record.sql

$types_dir/accounts/account.sql
$types_dir/accounts/account_authority.sql
$types_dir/accounts/comment_history.sql

$types_dir/blocks/latest_blocks.sql
$types_dir/blocks/block.sql
$types_dir/blocks/block_raw.sql
$types_dir/blocks/block_by_ops.sql
$types_dir/blocks/op_count_in_block.sql

$types_dir/operations/op_types.sql
$types_dir/operations/operation.sql

$types_dir/transactions/transaction.sql
"

DEFAULT_ENDPOINTS="
$endpoints_dir/endpoint_schema.sql

$endpoints_dir/witnesses/get_witnesses.sql
$endpoints_dir/witnesses/get_witness.sql
$endpoints_dir/witnesses/get_witness_voters.sql
$endpoints_dir/witnesses/get_witness_voters_num.sql
$endpoints_dir/witnesses/get_witness_votes_history.sql

$endpoints_dir/accounts/get_account.sql
$endpoints_dir/accounts/get_account_authority.sql
$endpoints_dir/accounts/get_ops_by_account.sql
$endpoints_dir/accounts/get_acc_op_types.sql
$endpoints_dir/accounts/get_comment_operations.sql

$endpoints_dir/blocks/get_latest_blocks.sql
$endpoints_dir/blocks/get_block.sql
$endpoints_dir/blocks/get_block_raw.sql
$endpoints_dir/blocks/get_ops_by_block_paging.sql
$endpoints_dir/blocks/get_op_count_in_block.sql
$endpoints_dir/blocks/get_block_op_types.sql

$endpoints_dir/block-numbers/get_block_by_op.sql
$endpoints_dir/block-numbers/get_head_block_num.sql
$endpoints_dir/block-numbers/get_hafbe_last_synced_block.sql
$endpoints_dir/block-numbers/get_block_by_time.sql

$endpoints_dir/operations/get_op_types.sql
$endpoints_dir/operations/get_matching_operation_types.sql
$endpoints_dir/operations/get_operation_keys.sql
$endpoints_dir/operations/get_operation.sql

$endpoints_dir/transactions/get_transaction.sql

$endpoints_dir/other/get_hafbe_version.sql
$endpoints_dir/other/get_input_type.sql
"

echo "Using default HAF block explorer types and endpoints directories"
echo "$DEFAULT_TYPES"

echo "$DEFAULT_ENDPOINTS"

# shellcheck disable=SC2086
python3 process_openapi.py $DEFAULT_OUTPUT $DEFAULT_TYPES $DEFAULT_ENDPOINTS
