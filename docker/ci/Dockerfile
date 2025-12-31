# syntax=registry.gitlab.syncad.com/hive/common-ci-configuration/dockerfile:1.11
# CI runner image based on common-ci-configuration docker-builder
FROM registry.gitlab.syncad.com/hive/common-ci-configuration/docker-builder:latest

# Copy JMeter and m2u from benchmark-test-runner
COPY --from=registry.gitlab.syncad.com/hive/common-ci-configuration/benchmark-test-runner:latest \
  --link /opt/tools/jmeter /opt/tools/jmeter
COPY --from=registry.gitlab.syncad.com/hive/common-ci-configuration/benchmark-test-runner:latest \
  --link /opt/tools/m2u /opt/tools/m2u

USER root
RUN <<-EOF
  # Install additional CI dependencies
  apk add --no-cache \
    7zip \
    curl \
    openjdk11-jre \
    postgresql16-client \
    python3 \
    py3-pip \
    py3-psycopg2 \
    sudo

  # Create symlinks for JMeter and m2u
  ln -s /opt/tools/jmeter/bin/jmeter.sh /usr/bin/jmeter
  ln -s /opt/tools/m2u/m2u /usr/bin/m2u
EOF

# Create hived user for compatibility with existing scripts (if not exists)
RUN id hived 2>/dev/null || adduser -D -s /bin/bash hived && \
    grep -q "^hived " /etc/sudoers || echo "hived ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

USER hived