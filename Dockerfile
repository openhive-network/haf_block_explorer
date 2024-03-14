# syntax=docker/dockerfile:1.5
ARG PAAS_PSQL_VERSION=11251948d5dd4867552f9b9836a9e02110304df5
FROM ghcr.io/alphagov/paas/psql:${PAAS_PSQL_VERSION} AS psql

RUN <<EOF
    set -e
    apk add --no-cache sudo git bash
    adduser -s /bin/bash -G users -D "haf_admin"
    echo "haf_admin ALL=(ALL:ALL) NOPASSWD:ALL" >> /etc/sudoers
EOF

USER haf_admin
WORKDIR /home/haf_admin

ENTRYPOINT [ "/bin/bash", "-c" ]

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
RUN <<-EOF
    set -e
    scripts/generate_version_sql.sh $(pwd)
    submodules/hafah/scripts/generate_version_sql.bash "/home/haf_admin/src/submodules/hafah" "/home/haf_admin/src/.git/modules/submodules/hafah"
EOF

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

COPY --chown=haf_admin:users scripts/install_app.sh /home/haf_admin/haf_block_explorer/scripts/install_app.sh
COPY --chown=haf_admin:users backend /home/haf_admin/haf_block_explorer/backend 
COPY --chown=haf_admin:users endpoints /home/haf_admin/haf_block_explorer/endpoints 
COPY --chown=haf_admin:users database /home/haf_admin/haf_block_explorer/database 
COPY --chown=haf_admin:users account_dump /home/haf_admin/haf_block_explorer/account_dump

COPY --chown=haf_admin:users submodules/btracker/scripts/install_app.sh /home/haf_admin/haf_block_explorer/submodules/btracker/scripts/install_app.sh
COPY --chown=haf_admin:users submodules/btracker/scripts/uninstall_app.sh /home/haf_admin/haf_block_explorer/submodules/btracker/scripts/uninstall_app.sh
COPY --chown=haf_admin:users submodules/btracker/db /home/haf_admin/haf_block_explorer/submodules/btracker/db
COPY --chown=haf_admin:users submodules/btracker/api /home/haf_admin/haf_block_explorer/submodules/btracker/api
COPY --chown=haf_admin:users submodules/btracker/endpoints /home/haf_admin/haf_block_explorer/submodules/btracker/endpoints
COPY --chown=haf_admin:users submodules/btracker/dump_accounts /home/haf_admin/haf_block_explorer/submodules/btracker/dump_accounts

COPY --chown=haf_admin:users submodules/hafah/scripts/install_app.sh /home/haf_admin/haf_block_explorer/submodules/hafah/scripts/install_app.sh
COPY --chown=haf_admin:users submodules/hafah/scripts/setup_postgres.sh /home/haf_admin/haf_block_explorer/submodules/hafah/scripts/setup_postgres.sh
COPY --chown=haf_admin:users submodules/hafah/scripts/common.sh /home/haf_admin/haf_block_explorer/submodules/hafah/scripts/common.sh
COPY --chown=haf_admin:users submodules/hafah/haf/scripts/create_haf_app_role.sh /home/haf_admin/haf_block_explorer/submodules/hafah/haf/scripts/create_haf_app_role.sh
COPY --chown=haf_admin:users submodules/hafah/haf/scripts/common.sh /home/haf_admin/haf_block_explorer/submodules/hafah/haf/scripts/common.sh
COPY --chown=haf_admin:users submodules/hafah/queries /home/haf_admin/haf_block_explorer/submodules/hafah/queries
COPY --chown=haf_admin:users submodules/hafah/postgrest /home/haf_admin/haf_block_explorer/submodules/hafah/postgrest
COPY --from=version-calculcation --chown=haf_admin:users /home/haf_admin/src/submodules/hafah/scripts/set_version_in_sql.pgsql /home/haf_admin/haf_block_explorer/submodules/hafah/scripts/set_version_in_sql.pgsql

COPY --chown=haf_admin:users scripts/process_blocks.sh /home/haf_admin/haf_block_explorer/scripts/process_blocks.sh
COPY --chown=haf_admin:users scripts/uninstall_app.sh /home/haf_admin/haf_block_explorer/scripts/uninstall_app.sh
COPY --chown=haf_admin:users docker/scripts/docker_entrypoint.sh /home/haf_admin/haf_block_explorer/scripts/docker_entrypoint.sh 
COPY --from=version-calculcation --chown=haf_admin:users /home/haf_admin/src/scripts/set_version_in_sql.pgsql /home/haf_admin/haf_block_explorer/scripts/set_version_in_sql.pgsql

WORKDIR /home/haf_admin/haf_block_explorer/scripts

ENTRYPOINT ["/home/haf_admin/haf_block_explorer/scripts/docker_entrypoint.sh"]