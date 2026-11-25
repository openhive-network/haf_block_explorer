#!/usr/bin/env bash
# =============================================================================
# HAF Block Explorer: the image's haf_app_driver.py accepts what process_blocks.sh passes
# =============================================================================
#
# The image takes haf_app_driver.py from its psql base image (Dockerfile's
# PSQL_CLIENT_VERSION). A driver older than an option scripts/process_blocks.sh
# passes it exits with "unrecognized arguments", and under a restart policy that
# is a block processor that never processes a block. This runs the given image's
# own driver with --help and checks that it lists every --option= that
# process_blocks.sh puts on the driver's command line (the exec line and the
# arrays it expands there). Needs docker and the image; no database.
#
# EXIT CODES:
#   0 - Passed
#   1 - Failed
#   2 - Usage error
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROCESS_BLOCKS="$SCRIPT_DIR/../../scripts/process_blocks.sh"

print_help() {
    cat <<EOH
Usage: $0 IMAGE

Checks that IMAGE's haf_app_driver.py --help lists every option
scripts/process_blocks.sh passes the driver.
EOH
}

case "${1:-}" in
    --help|-h) print_help; exit 0 ;;
    ''|-*) print_help >&2; exit 2 ;;
esac
image="$1"

# The arrays expanded on the exec line are set as name_arg=(--option=...)
mapfile -t options < <(
    grep -E '^[[:space:]]*exec haf_app_driver\.py |[a-z_]+_arg=\(--' "$PROCESS_BLOCKS" \
        | grep -oE -- '--[a-z][a-z-]*=' | tr -d '=' | sort -u
)
if ! printf '%s\n' "${options[@]}" | grep -qx -- '--app'; then
    echo "FAIL  could not read the driver options from $PROCESS_BLOCKS (found: ${options[*]:-none})"
    exit 1
fi
echo "Options process_blocks.sh passes haf_app_driver.py: ${options[*]}"

if ! help="$(docker run --rm --entrypoint haf_app_driver.py "$image" --help 2>&1)"; then
    echo "FAIL  haf_app_driver.py --help in $image failed:"
    echo "$help"
    exit 1
fi

missing=()
for option in "${options[@]}"; do
    grep -qE -- "(^|[[:space:]\[,])${option}([=[:space:],]|$)" <<<"$help" || missing+=("$option")
done
if [ "${#missing[@]}" -gt 0 ]; then
    echo "FAIL  haf_app_driver.py in $image does not accept: ${missing[*]}"
    echo "$help"
    exit 1
fi
echo "PASS  haf_app_driver.py in $image accepts every option process_blocks.sh passes"
