# syntax=registry.gitlab.syncad.com/hive/common-ci-configuration/dockerfile:1.11
ARG PSQL_CLIENT_VERSION=14-2
FROM registry.gitlab.syncad.com/hive/common-ci-configuration/psql:$PSQL_CLIENT_VERSION AS psql

FROM psql as daemontools
USER root
RUN <<EOF
    set -e
    echo http://dl-cdn.alpinelinux.org/alpine/edge/community > /etc/apk/repositories
    apk --no-cache add daemontools-encore
EOF

FROM psql as version-calculcation
ARG API_VERSION="dev"
USER root
RUN addgroup -S users 2>/dev/null || true && adduser -D -u 1000 -G users hived 2>/dev/null || true
USER hived

COPY --chown=hived:users . /home/hived/src
WORKDIR /home/hived/src
RUN scripts/generate_version_sql.sh $(pwd)
RUN find . -name 'endpoint_schema.sql' -o -name 'hafah_openapi.sql' | while read -r f; do \
         sed -i 's|"version": "[^"]*"|"version": "'"$API_VERSION"'"|' "$f"; \
         sed -i 's|^  version: .*|  version: '"$API_VERSION"'|' "$f"; \
       done

FROM psql as full

ARG BUILD_TIME
ARG GIT_COMMIT_SHA
ARG GIT_CURRENT_BRANCH
ARG GIT_LAST_LOG_MESSAGE
ARG GIT_LAST_COMMITTER
ARG GIT_LAST_COMMIT_DATE
LABEL org.opencontainers.image.created="$BUILD_TIME"
LABEL org.opencontainers.image.url="https://hive.io/"
LABEL org.opencontainers.image.documentation="https://gitlab.syncad.com/hive/haf_block_explorer"
LABEL org.opencontainers.image.source="https://gitlab.syncad.com/hive/haf_block_explorer"
#LABEL org.opencontainers.image.version="${VERSION}"
LABEL org.opencontainers.image.revision="$GIT_COMMIT_SHA"
LABEL org.opencontainers.image.licenses="MIT"
LABEL org.opencontainers.image.ref.name="HAF Block Explorer"
LABEL org.opencontainers.image.title="HAF Block Explorer Image"
LABEL org.opencontainers.image.description="Runs HAF Block Explorer application"
LABEL io.hive.image.branch="$GIT_CURRENT_BRANCH"
LABEL io.hive.image.commit.log_message="$GIT_LAST_LOG_MESSAGE"
LABEL io.hive.image.commit.author="$GIT_LAST_COMMITTER"
LABEL io.hive.image.commit.date="$GIT_LAST_COMMIT_DATE"

COPY --from=daemontools /usr/bin/tai64n /usr/bin/tai64nlocal /usr/bin/

RUN mkdir -p /home/hived/haf_block_explorer/scripts
RUN mkdir -p /home/hived/haf_block_explorer/queries
RUN mkdir -p /home/hived/haf_block_explorer/postgrest
RUN mkdir -p /home/hived/haf_block_explorer/haf/scripts

USER root

RUN <<EOF
  set -e
  apk --no-cache add curl
  addgroup -S users 2>/dev/null || true
  adduser -D -u 1000 -G users hived 2>/dev/null || true
  mkdir /app
  chown hived /app
EOF

USER hived

COPY --chown=hived:users docker/scripts/block-processing-healthcheck.sh /app/

COPY --chown=hived:users backend /home/hived/haf_block_explorer/backend
COPY --from=version-calculcation --chown=hived:users /home/hived/src/endpoints /home/hived/haf_block_explorer/endpoints
COPY --chown=hived:users db /home/hived/haf_block_explorer/db

COPY --chown=hived:users scripts/install_app.sh /home/hived/haf_block_explorer/scripts/install_app.sh
COPY --chown=hived:users scripts/process_blocks.sh /home/hived/haf_block_explorer/scripts/process_blocks.sh
COPY --chown=hived:users scripts/uninstall_app.sh /home/hived/haf_block_explorer/scripts/uninstall_app.sh
COPY --chown=hived:users scripts/generate_version_sql.sh /home/hived/haf_block_explorer/scripts/generate_version_sql.sh
COPY --chown=hived:users docker/scripts/docker_entrypoint.sh /home/hived/haf_block_explorer/scripts/docker_entrypoint.sh
COPY --from=version-calculcation --chown=hived:users /home/hived/src/scripts/set_version_in_sql.pgsql /home/hived/haf_block_explorer/scripts/set_version_in_sql.pgsql

WORKDIR /home/hived/haf_block_explorer/scripts

SHELL ["/bin/bash", "-c"]

ENTRYPOINT ["/home/hived/haf_block_explorer/scripts/docker_entrypoint.sh"]