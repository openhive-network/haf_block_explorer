# syntax=registry.gitlab.syncad.com/hive/common-ci-configuration/dockerfile:1.5
# THe lastest CI runner image from balance_tracker repository
FROM registry.gitlab.syncad.com/hive/balance_tracker/ci-runner:docker-24.0.1-10

USER root
RUN <<-EOF
  # Install system dependencies
  apk add --no-cache 7zip
EOF

USER hived