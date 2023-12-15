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
RUN apk --no-cache add daemontools-encore

FROM psql as full
COPY --from=daemontools /usr/bin/tai64n /usr/bin/tai64nlocal /usr/bin/

RUN mkdir -p /haf_block_explorer/scripts
RUN mkdir -p /haf_block_explorer/queries
RUN mkdir -p /haf_block_explorer/postgrest
RUN mkdir -p /haf_block_explorer/haf/scripts

COPY scripts/install_app.sh /haf_block_explorer/scripts/install_app.sh
COPY backend /haf_block_explorer/backend 
COPY endpoints /haf_block_explorer/endpoints 
COPY database /haf_block_explorer/database 
COPY account_dump /haf_block_explorer/account_dump 

COPY scripts/install_app.sh /haf_block_explorer/scripts/install_app.sh 
COPY scripts/process_blocks.sh /haf_block_explorer/scripts/process_blocks.sh
COPY scripts/uninstall_app.sh /haf_block_explorer/scripts/uninstall_app.sh 
COPY docker/scripts/docker_entrypoint.sh /haf_block_explorer/scripts/docker_entrypoint.sh 
COPY set_version_in_sql.pgsql /haf_block_explorer/scripts/set_version_in_sql.pgsql

WORKDIR /haf_block_explorer/scripts

ENTRYPOINT ["/haf_block_explorer/scripts/docker_entrypoint.sh"]