# The image AIDEV runs this project's checks in. AIDEV builds it on the base
# .aidev/project.yaml `environment.base` follows (common-ci-configuration's
# python-test-tools:develop, the image CI's lint and test templates run in) and
# rebuilds it when that tag moves, so the tool versions are ccc's docker-bake.hcl's
# and none is pinned here. Checks run with the caller's uid and, for the slots that
# reach the shared HAF, on the per-run network its relay is on; nothing is installed
# at run time. The base provides bash, git, psql, shellcheck, sqlfluff, postgrest,
# pytest, pytest-xdist and tavern; this adds what it lacks:
#
#   + psycopg2 (tests/regression/load_expected_data.py)
#   + hive/tests_api (validate_response, the tavern tests' comparator), from its
#     default branch as CI's pattern-test clones it
#   + HAfAH's SQL sources at /opt/hafah, from the HAfAH image CI's
#     docker/docker-compose.yml installs (HAFAH_REGISTRY/HAFAH_VERSION in
#     .gitlab-ci.yml, HAfAH fe9aaf53): haf_block_explorer's SQL calls hafah_backend
#   + the OpenResty of Dockerfile.rewriter's base image (common-ci-configuration's
#     nginx at 1d952fd1, with the hive.rpc_form module) at its own path, and the
#     Alpine loader and libraries it links (the loader reads its library path from
#     /etc/ld-musl-x86_64.path): the rewriter step runs the rewriter image's
#     nginx with the repository's config, rules and argument map
ARG BASE_IMAGE

# common-ci-configuration/nginx:1d952fd19118762d0e66f91953e194ff08e69bb0, Dockerfile.rewriter's
# FROM; move both together.
FROM registry.gitlab.syncad.com/hive/common-ci-configuration/nginx@sha256:e173b651aff04b3735f870068549281c417801ea64b192cf7c8cc4bce5a91815 AS rewriter

# HAFAH_VERSION in .gitlab-ci.yml; move both together.
FROM registry.gitlab.syncad.com/hive/hafah@sha256:71cf4c7c2ca9f43e89047ee98a87659adeb0b4db52c00a88a34a540f9c40a9f2 AS hafah

FROM ${BASE_IMAGE}

USER root

RUN pip install --no-cache-dir --root-user-action=ignore \
        psycopg2-binary \
        "git+https://gitlab.syncad.com/hive/tests_api.git"

COPY --from=hafah /home/hafah_user/app /opt/hafah

COPY --from=rewriter /usr/local/openresty /usr/local/openresty
COPY --from=rewriter /lib/ld-musl-x86_64.so.1 /lib/ld-musl-x86_64.so.1
COPY --from=rewriter /usr/lib/libz.so.1 /usr/lib/libgcc_s.so.1 /opt/musl/lib/
RUN echo /opt/musl/lib > /etc/ld-musl-x86_64.path

ENV HOME=/tmp
ENTRYPOINT []
CMD ["bash"]
