# syntax=registry.gitlab.syncad.com/hive/common-ci-configuration/dockerfile:1.11
# CI runner image based on common-ci-configuration docker-builder
FROM registry.gitlab.syncad.com/hive/common-ci-configuration/docker-builder:latest

USER root
RUN <<-EOF
  # Install additional CI dependencies
  apk add --no-cache \
    7zip \
    postgresql16-client \
    sudo
EOF

# Create hived user for compatibility with existing scripts (if not exists)
RUN id hived 2>/dev/null || adduser -D -s /bin/bash hived && \
    grep -q "^hived " /etc/sudoers || echo "hived ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

USER hived