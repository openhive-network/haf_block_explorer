# Global variables
variable "CI_REGISTRY_IMAGE" {
  default = "registry.gitlab.syncad.com/hive/haf_block_explorer"
}
variable "CI_COMMIT_SHORT_SHA" {
  default = ""
}
variable "CI_COMMIT_TAG" {
  default = ""
}
variable "CI_COMMIT_BRANCH" {
  default = "develop"
}
variable "CI_DEFAULT_BRANCH" {
  default = "develop"
}
variable "TAG" {
  default = "latest"
}
variable "TAG_CI" {
  default = "docker-24.0.1-4"
}
variable "PSQL_CLIENT_VERSION" {
  default = "14"
}
variable "BUILD_TIME" {}
variable "GIT_COMMIT_SHA" {}
variable "GIT_CURRENT_BRANCH" {}
variable "GIT_LAST_LOG_MESSAGE" {}
variable "GIT_LAST_COMMITTER" {}
variable "GIT_LAST_COMMIT_DATE" {}

# Functions
function "notempty" {
  params = [variable]
  result = notequal("", variable)
}

function "registry-name" {
  params = [name, suffix]
  result = notempty(suffix) ? "${CI_REGISTRY_IMAGE}/${name}/${suffix}" : "${CI_REGISTRY_IMAGE}/${name}"
}

# Target groups
group "default" {
  targets = ["full"]
}

# Targets
target "psql" {
  dockerfile = "Dockerfile"
  target = "psql"
  tags = [
    "${registry-name("psql", "")}:${PSQL_CLIENT_VERSION}"
  ]
  platforms = [
    "linux/amd64"
  ]
  output = [
    "type=docker"
  ]
}

target "psql-ci" {
  inherits = ["psql"]
  output = [
    "type=registry"
  ]
}

## Locally tag image with "$TAG",
## which is "latest" by default
target "full" {
  inherits = ["psql"]
  target = "full"
  tags = [
    "${CI_REGISTRY_IMAGE}:${TAG}"
  ]
  args = {
    BUILD_TIME = "${BUILD_TIME}",
    GIT_COMMIT_SHA = "${GIT_COMMIT_SHA}",
    GIT_CURRENT_BRANCH = "${GIT_CURRENT_BRANCH}",
    GIT_LAST_LOG_MESSAGE = "${GIT_LAST_LOG_MESSAGE}",
    GIT_LAST_COMMITTER = "${GIT_LAST_COMMITTER}",
    GIT_LAST_COMMIT_DATE = "${GIT_LAST_COMMIT_DATE}",
  }
  output = [
    "type=docker"
  ]
}

## On default branch, tag image with "latest" and commit hash,
## on any other branch tag image with just commit hash
target "full-ci" {
  inherits = ["full"]
  contexts = {
    psql = "docker-image://${registry-name("psql", "")}:${PSQL_CLIENT_VERSION}"
  }
  cache-from = [
    "type=registry,ref=${registry-name("cache", "")}:${PSQL_CLIENT_VERSION}"
  ]
  cache-to = [
    "type=registry,mode=max,ref=${registry-name("cache", "")}:${PSQL_CLIENT_VERSION}"
  ]
  tags = [
    equal(CI_COMMIT_BRANCH, CI_DEFAULT_BRANCH) ? "${CI_REGISTRY_IMAGE}:latest": "",
    notempty(CI_COMMIT_SHORT_SHA) ? "${CI_REGISTRY_IMAGE}:${CI_COMMIT_SHORT_SHA}" : "",
    notempty(CI_COMMIT_TAG) ? "${CI_REGISTRY_IMAGE}:${CI_COMMIT_TAG}": ""
  ]
  output = [
    "type=registry"
  ]
}

target "ci-runner" {
  dockerfile = "Dockerfile"
  context = "docker/ci"
  tags = [
    "${registry-name("ci-runner", "")}:${TAG_CI}"
  ]
  output = [
    "type=docker"
  ]
}

target "ci-runner-ci" {
  inherits = ["ci-runner"]
  cache-from = [
    "type=registry,ref=${registry-name("ci-runner", "cache")}:${TAG_CI}"
  ]
  cache-to = [
    "type=registry,mode=max,image-manifest=true,ref=${registry-name("ci-runner", "cache")}:${TAG_CI}"
  ]
  tags = [
    "${registry-name("ci-runner", "")}:${TAG_CI}"
  ]
  output = [
    "type=registry"
  ]
}