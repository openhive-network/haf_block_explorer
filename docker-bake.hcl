# Global variables
variable "CI_REGISTRY_IMAGE" {
    default = "registry.gitlab.syncad.com/hive/haf_block_explorer"
}
variable "TAG_CI" {
  default = "docker-24.0.1-3"
}
variable "PSQL_CLIENT_VERSION" {
  default = "14"
}

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
  targets = ["psql"]
}

# Targets
target "psql" {
  dockerfile = "Dockerfile"
  tags = [
    "${registry-name("psql", "")}:${PSQL_CLIENT_VERSION}"
  ]
  platforms = [
    "linux/amd64"
  ]
}

target "ci-runner" {
  dockerfile = "Dockerfile"
  context = "docker/ci"
  tags = [
    "${registry-name("ci-runner", "")}:${TAG_CI}"
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
}