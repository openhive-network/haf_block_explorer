#! /bin/bash

set -e

print_help () {
    cat <<-EOF
Usage: $0 <source directory> [OPTION[=VALUE]]...

Build any Docker image defined as a target in docker-bake.hcl
OPTIONS:
  --registry=URL        Docker registry to assign the image to (default: 'registry.gitlab.syncad.com/hive/haf_block_explorer')
  --tag=TAG             Docker tag to be build (defaults set in docker-bake.hcl)
  --target=TARGET       Target defined in docker-bake.hcl (default: 'default' - builds full image)
  --progress=TYPE       Determines how to display build progress (default: 'auto')
  --help|-h|-?          Display this help screen and exit
EOF
}

CI_REGISTRY_IMAGE=${CI_REGISTRY_IMAGE:-"registry.gitlab.syncad.com/hive/haf_block_explorer"}
PROGRESS_DISPLAY=${PROGRESS_DISPLAY:-"auto"}
TARGET=${TARGET:-"default"}

while [ $# -gt 0 ]; do
  case "$1" in
    --registry=*)
        arg="${1#*=}"
        CI_REGISTRY_IMAGE="$arg"
        ;;
    --tag=*)
        arg="${1#*=}"
        BASE_TAG="$arg"
        ;;    
    --progress=*)
        arg="${1#*=}"
        PROGRESS_DISPLAY="$arg"
        ;;
    --target=*)
        arg="${1#*=}"
        TARGET="$arg"
        ;;
    --help|-h|-\?)
        print_help
        exit 0
        ;;
    *)
        if [ -z "$SRCROOTDIR" ];
        then
          SRCROOTDIR="${1}"
        else
          echo "ERROR: '$1' is not a valid option/positional argument"
          echo
          print_help
          exit 2
        fi
        ;;
    esac
    shift
done


pushd "$SRCROOTDIR"

case ${TARGET:-} in
  default|full|full-ci)
    scripts/ci-helpers/build_instance.sh "$BASE_TAG" "$SRCROOTDIR" "$CI_REGISTRY_IMAGE" --progress="$PROGRESS_DISPLAY"
    ;;
  ci-runner|ci-runner-ci)
    scripts/build_ci-runner_image.sh "$SRCROOTDIR" --registry="$CI_REGISTRY_IMAGE" --tag="$BASE_TAG" --progress="$PROGRESS_DISPLAY" --target="$TARGET"
    ;;
esac

popd