# syntax=docker/dockerfile:1.5
ARG PSQL_CLIENT_VERSION=14-1
ARG PYTHON_IMAGE_VERSION=6b9e9e75ec5263939450936a4f8348dfbca3666d #commit from common-ci-configuration develop
FROM registry.gitlab.syncad.com/hive/common-ci-configuration/psql:$PSQL_CLIENT_VERSION AS psql

FROM psql as daemontools
USER root
RUN <<EOF
    set -e
    echo http://dl-cdn.alpinelinux.org/alpine/edge/community > /etc/apk/repositories
    apk --no-cache add daemontools-encore
EOF

FROM psql as version-calculcation

COPY --chown=haf_admin:users scripts /home/haf_admin/src/scripts
COPY --chown=haf_admin:users .git /home/haf_admin/src/.git
WORKDIR /home/haf_admin/src
RUN scripts/generate_version_sql.sh $(pwd)

FROM registry.gitlab.syncad.com/hive/common-ci-configuration/python-scripts:$PYTHON_IMAGE_VERSION AS openapi-generator

ARG GIT_COMMIT_SHA
ENV GIT_COMMIT_SHA=${GIT_COMMIT_SHA}

RUN pip3 install deepmerge jsonpointer pyyaml

COPY openapi-gen-input /haf_block_explorer/openapi-gen-input
COPY scripts /haf_block_explorer/scripts
COPY submodules/haf/scripts/process_openapi.py /haf_block_explorer/submodules/haf/scripts/

WORKDIR /haf_block_explorer
RUN echo "Processing git version: ${GIT_COMMIT_SHA}" && ./scripts/openapi_rewrite.sh --version "${GIT_COMMIT_SHA}" --swagger_json swagger-doc.json

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

COPY --chown=haf_admin:users docker/scripts/block-processing-healthcheck.sh /app/

COPY --chown=haf_admin:users backend /home/haf_admin/haf_block_explorer/backend
COPY --chown=haf_admin:users database /home/haf_admin/haf_block_explorer/database
COPY --chown=haf_admin:users account_dump /home/haf_admin/haf_block_explorer/account_dump

COPY --chown=haf_admin:users \
  scripts/install_app.sh \
  scripts/process_blocks.sh \
  scripts/uninstall_app.sh \
  docker/scripts/docker_entrypoint.sh \
  /home/haf_admin/haf_block_explorer/scripts/

COPY --from=version-calculcation --chown=haf_admin:users /home/haf_admin/src/scripts/set_version_in_sql.pgsql /home/haf_admin/haf_block_explorer/scripts/set_version_in_sql.pgsql
COPY --from=openapi-generator --chown=haf_admin:users /haf_block_explorer/scripts/output/openapi-gen-input /home/haf_admin/haf_block_explorer/
COPY --from=openapi-generator --chown=haf_admin:users /haf_block_explorer/scripts/output/swagger-doc.json /home/haf_admin/haf_block_explorer/endpoints

USER haf_admin

WORKDIR /home/haf_admin/haf_block_explorer/scripts

SHELL ["/bin/bash", "-c"]

ENTRYPOINT ["/home/haf_admin/haf_block_explorer/scripts/docker_entrypoint.sh"]