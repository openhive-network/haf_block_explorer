# syntax=docker/dockerfile:1.5
ARG PSQL_CLIENT_VERSION=14-1
FROM registry.gitlab.syncad.com/hive/common-ci-configuration/psql:$PSQL_CLIENT_VERSION AS psql

FROM psql as daemontools
USER root
RUN <<EOF
    set -e
    echo http://dl-cdn.alpinelinux.org/alpine/edge/community > /etc/apk/repositories
    apk --no-cache add daemontools-encore
EOF

FROM psql as version-calculcation

COPY --chown=haf_admin:users . /home/haf_admin/src
WORKDIR /home/haf_admin/src
RUN scripts/generate_version_sql.sh $(pwd)

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

RUN mkdir -p /home/haf_admin/haf_block_explorer/scripts
RUN mkdir -p /home/haf_admin/haf_block_explorer/queries
RUN mkdir -p /home/haf_admin/haf_block_explorer/postgrest
RUN mkdir -p /home/haf_admin/haf_block_explorer/haf/scripts

USER root

RUN <<EOF
  set -e
  mkdir /app
  chown haf_admin /app
EOF

USER haf_admin

COPY --chown=haf_admin:users docker/scripts/block-processing-healthcheck.sh /app/

COPY --chown=haf_admin:users scripts/install_app.sh /home/haf_admin/haf_block_explorer/scripts/install_app.sh
COPY --chown=haf_admin:users backend /home/haf_admin/haf_block_explorer/backend 
COPY --chown=haf_admin:users endpoints /home/haf_admin/haf_block_explorer/endpoints 
COPY --chown=haf_admin:users database /home/haf_admin/haf_block_explorer/database 
COPY --chown=haf_admin:users account_dump /home/haf_admin/haf_block_explorer/account_dump 

COPY --chown=haf_admin:users scripts/install_app.sh /home/haf_admin/haf_block_explorer/scripts/install_app.sh 
COPY --chown=haf_admin:users scripts/process_blocks.sh /home/haf_admin/haf_block_explorer/scripts/process_blocks.sh
COPY --chown=haf_admin:users scripts/uninstall_app.sh /home/haf_admin/haf_block_explorer/scripts/uninstall_app.sh 
COPY --chown=haf_admin:users docker/scripts/docker_entrypoint.sh /home/haf_admin/haf_block_explorer/scripts/docker_entrypoint.sh 
COPY --from=version-calculcation --chown=haf_admin:users /home/haf_admin/src/scripts/set_version_in_sql.pgsql /home/haf_admin/haf_block_explorer/scripts/set_version_in_sql.pgsql

WORKDIR /home/haf_admin/haf_block_explorer/scripts

SHELL ["/bin/bash", "-c"]

ENTRYPOINT ["/home/haf_admin/haf_block_explorer/scripts/docker_entrypoint.sh"]