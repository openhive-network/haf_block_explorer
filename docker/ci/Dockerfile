# syntax=docker/dockerfile:1.5
# THe lastest CI runner image from balance_tracker repository
FROM registry.gitlab.syncad.com/hive/balance_tracker/ci-runner:docker-24.0.1-5

USER root
RUN <<-EOF
  # Install system dependencies
  apk add --no-cache py3-psycopg2 7zip
EOF

USER hived