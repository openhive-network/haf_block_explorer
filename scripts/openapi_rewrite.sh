#!/bin/bash

set -e
set -o pipefail

SCRIPTDIR="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 || exit 1; pwd -P )"

haf_dir="${SCRIPTDIR}/../submodules/haf"
endpoints="${SCRIPTDIR}/../endpoints"
types="${SCRIPTDIR}/../backend/types"

# Default directories with fixed order if none provided
OUTPUT="$SCRIPTDIR/output"
DEFAULT_TYPES=(
"$types/backend_types.sql"
"$types/witnesses/witness.sql"
"$types/witnesses/witness_voters.sql"
"$types/witnesses/witness_votes_history_record.sql"
"$types/accounts/account.sql"
"$types/accounts/account_authority.sql"
"$types/accounts/permlink_history.sql"
"$types/blocks/latest_blocks.sql"
"$types/operations/operation.sql"
"$types/operations/op_types_count.sql"
)

ENDPOINTS_IN_ORDER=(
"$endpoints/endpoint_schema.sql"
"$endpoints/witnesses/get_witnesses.sql"
"$endpoints/witnesses/get_witness.sql"
"$endpoints/witnesses/get_witness_voters.sql"
"$endpoints/witnesses/get_witness_voters_num.sql"
"$endpoints/witnesses/get_witness_votes_history.sql"
"$endpoints/accounts/get_account.sql"
"$endpoints/accounts/get_account_authority.sql"
"$endpoints/accounts/get_comment_permlinks.sql"
"$endpoints/accounts/get_comment_operations.sql"
"$endpoints/block-numbers/get_block_by_op.sql"
"$endpoints/other/get_hafbe_version.sql"
"$endpoints/other/get_hafbe_last_synced_block.sql"
"$endpoints/other/get_input_type.sql"
"$endpoints/other/get_latest_blocks.sql"
)

# Function to install pip3
install_pip() {
    echo "pip3 is not installed. Installing now..."
    # Ensure Python 3 is installed
    if ! command -v python3 &> /dev/null; then
        echo "Python 3 is not installed. Please install Python 3 first."
        exit 1
    fi
    # Try to install pip3
    sudo apt-get update
    sudo apt-get install -y python3-pip
    if ! command -v pip3 &> /dev/null; then
        echo "pip3 installation failed. Please install pip3 manually."
        exit 1
    fi
}

# Check if pip3 is installed
if ! command -v pip3 &> /dev/null; then
    install_pip
fi

# Check if deepmerge is installed
if python3 -c "import deepmerge" &> /dev/null; then
    echo "deepmerge is already installed."
else
    echo "deepmerge is not installed. Installing now..."
    pip3 install deepmerge
    echo "deepmerge has been installed."
fi

# Check if jsonpointer is installed
if python3 -c "import jsonpointer" &> /dev/null; then
    echo "jsonpointer is already installed."
else
    echo "jsonpointer is not installed. Installing now..."
    pip3 install jsonpointer
    echo "jsonpointer has been installed."
fi

echo "Using endpoints sources:"
echo "${ENDPOINTS_IN_ORDER[@]}"
echo "Using types sources:"
echo "${DEFAULT_TYPES[@]}"

rm -rfv "${OUTPUT}"

pushd "${SCRIPTDIR}"

# run openapi rewrite script
# shellcheck disable=SC2086
python3 "${haf_dir}/scripts/process_openapi.py" "$@" "${OUTPUT}" "${DEFAULT_TYPES[@]}" "${ENDPOINTS_IN_ORDER[@]}"

echo "Rewritten endpoint scripts and rewrite_rules.conf file saved in ${OUTPUT}"

popd
