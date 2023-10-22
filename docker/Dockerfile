FROM alpine:3.18.3 as daemontools
RUN apk --no-cache add daemontools-encore

FROM alpine:3.18.3
RUN apk --no-cache add postgresql14-client bash
COPY --from=daemontools /usr/bin/tai64n /usr/bin/tai64nlocal /usr/bin

RUN mkdir -p /haf_block_explorer/scripts
RUN mkdir -p /haf_block_explorer/queries
RUN mkdir -p /haf_block_explorer/postgrest
RUN mkdir -p /haf_block_explorer/haf/scripts

COPY scripts/setup_db.sh /haf_block_explorer/scripts/setup_db.sh
COPY backend /haf_block_explorer/backend 
COPY endpoints /haf_block_explorer/endpoints 
COPY database /haf_block_explorer/database 
COPY account_dump /haf_block_explorer/account_dump 

COPY scripts/setup_db.sh /haf_block_explorer/scripts/setup_db.sh 
COPY scripts/process_blocks.sh /haf_block_explorer/scripts/process_blocks.sh
COPY scripts/drop_db.sh /haf_block_explorer/scripts/drop_db.sh 
COPY docker/docker_entrypoint.sh /haf_block_explorer/scripts/docker_entrypoint.sh 
COPY set_version_in_sql.pgsql /haf_block_explorer/set_version_in_sql.pgsql

WORKDIR /haf_block_explorer/scripts

ENTRYPOINT ["/haf_block_explorer/scripts/docker_entrypoint.sh"]
