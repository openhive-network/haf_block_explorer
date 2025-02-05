#! /bin/bash

set -e

print_help () {
cat <<-EOF
Usage: $0 <image_tag> <src_dir> <registry_url> [OPTION[=VALUE]]...

A wrapper script for building HAF Block Explorer Docker image
OPTIONS:
    --progress=TYPE       Determines how to display build progress (default: 'auto')
    --push                Allows to automatically push built image to the registry
    --help|-h|-?          Display this help screen and exit
EOF
}

PROGRESS_DISPLAY=${PROGRESS_DISPLAY:-"auto"}
IMAGE_OUTPUT="--load"

while [ $# -gt 0 ]; do
  case "$1" in
    --progress=*)
      arg="${1#*=}"
      PROGRESS_DISPLAY="$arg"
      ;;
    --push)
      IMAGE_OUTPUT="--push"
      ;;
    --help|-h|-\?)
      print_help
      exit 0
      ;;
    *)
      if [ -z "$BUILD_IMAGE_TAG" ];
      then
        BUILD_IMAGE_TAG="${1}"
      elif [ -z "$SRCROOTDIR" ];
      then
        SRCROOTDIR="${1}"
      elif [ -z "$REGISTRY" ];
      then
        REGISTRY=${1}
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

_TST_IMGTAG=${BUILD_IMAGE_TAG:?"Missing argument #1 - image tag to be built"}
_TST_SRCDIR=${SRCROOTDIR:?"Missing arg #2 - source directory"}
_TST_REGISTRY=${REGISTRY:?"Missing arg #3 - container registry URL"}

TARGET="full"

export TAG=$BUILD_IMAGE_TAG

pushd "$SRCROOTDIR"

# All the variables below must be declared and assigned separately
# for 'set -e' to work correctly. See https://www.shellcheck.net/wiki/SC2155
# for an explanation

BUILD_TIME="$(date -uIseconds)"
export BUILD_TIME

GIT_COMMIT_SHA="$(git rev-parse HEAD || true)"
if [ -z "$GIT_COMMIT_SHA" ]; then
  GIT_COMMIT_SHA="[unknown]"
fi
export GIT_COMMIT_SHA

GIT_CURRENT_BRANCH="$(git branch --show-current || true)"
if [ -z "$GIT_CURRENT_BRANCH" ]; then
  GIT_CURRENT_BRANCH="$(git describe --abbrev=0 --all --exclude 'pipelines/*' | sed 's/^.*\///' || true)"
  if [ -z "$GIT_CURRENT_BRANCH" ]; then
    GIT_CURRENT_BRANCH="[unknown]"
  fi
fi
export GIT_CURRENT_BRANCH

GIT_LAST_LOG_MESSAGE="$(git log -1 --pretty=%B || true)"
if [ -z "$GIT_LAST_LOG_MESSAGE" ]; then
  GIT_LAST_LOG_MESSAGE="[unknown]"
fi
export GIT_LAST_LOG_MESSAGE

GIT_LAST_COMMITTER="$(git log -1 --pretty="%an <%ae>" || true)"
if [ -z "$GIT_LAST_COMMITTER" ]; then
  GIT_LAST_COMMITTER="[unknown]"
fi
export GIT_LAST_COMMITTER

GIT_LAST_COMMIT_DATE="$(git log -1 --pretty="%aI" || true)"
if [ -z "$GIT_LAST_COMMIT_DATE" ]; then
  GIT_LAST_COMMIT_DATE="[unknown]"
fi
export GIT_LAST_COMMIT_DATE

docker buildx bake --provenance=false "${IMAGE_OUTPUT}" --progress="$PROGRESS_DISPLAY" "$TARGET"

# This script can be called with BUILD_IMAGE_TAG set to either a short commit hash
# or a release tag like 1.27.5rc6.  If it's a release tag, we need to build the
# image differently to include the release string in.
case "$BUILD_IMAGE_TAG" in
  1.*)
    REWRITER_TARGET=with_tag
    TAG_BUILD_ARGS="--build-arg GIT_COMMIT_TAG=$BUILD_IMAGE_TAG"
    ;;
  *)
    REWRITER_TARGET=without_tag
    ;;
esac

# shellcheck disable=SC2086
docker buildx build \
    --progress="$PROGRESS_DISPLAY" \
    --build-arg BUILD_TIME="$BUILD_TIME" \
    --build-arg GIT_COMMIT_SHA="$GIT_COMMIT_SHA" \
    --build-arg GIT_CURRENT_BRANCH="$GIT_CURRENT_BRANCH" \
    --build-arg GIT_LAST_LOG_MESSAGE="$GIT_LAST_LOG_MESSAGE" \
    --build-arg GIT_LAST_COMMITTER="$GIT_LAST_COMMITTER" \
    --build-arg GIT_LAST_COMMIT_DATE="$GIT_LAST_COMMIT_DATE" \
    --target=$REWRITER_TARGET \
    $TAG_BUILD_ARGS \
    --tag "$REGISTRY/postgrest-rewriter:$BUILD_IMAGE_TAG" \
    "${IMAGE_OUTPUT}" \
    --file Dockerfile .

echo "APP_IMAGE_NAME=$REGISTRY:$BUILD_IMAGE_TAG" > haf_be_docker_image_name.env
{
  echo "APP_IMAGE_VERSION=$BUILD_IMAGE_TAG"
  echo "REWRITER_IMAGE_NAME=$REGISTRY/postgrest-rewriter:$BUILD_IMAGE_TAG"
} >> haf_be_docker_image_name.env

popd

# TODO remove it when build_and_publish_instance.sh script (shared from hive repo) will not need such tags
docker tag "$REGISTRY:$BUILD_IMAGE_TAG" "$REGISTRY/instance:$BUILD_IMAGE_TAG"
docker tag "$REGISTRY:$BUILD_IMAGE_TAG" "$REGISTRY/minimal-instance:$BUILD_IMAGE_TAG"
