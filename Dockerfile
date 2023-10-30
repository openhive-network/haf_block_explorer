# syntax=docker/dockerfile:1.5
ARG PAAS_PSQL_VERSION=11251948d5dd4867552f9b9836a9e02110304df5
FROM ghcr.io/alphagov/paas/psql:${PAAS_PSQL_VERSION}

RUN <<EOF
    set -e
    apk add --no-cache sudo git bash
    adduser -s /bin/bash -G users -D "haf_admin"
    echo "haf_admin ALL=(ALL:ALL) NOPASSWD:ALL" >> /etc/sudoers
EOF

USER haf_admin
WORKDIR /home/haf_admin

ENTRYPOINT [ "/bin/bash", "-c" ]