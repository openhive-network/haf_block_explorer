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
ARG BASE_IMAGE

# HAFAH_VERSION in .gitlab-ci.yml; move both together.
FROM registry.gitlab.syncad.com/hive/hafah@sha256:5700227393d79446f0a4a46eab2d4f2cb88cf7ef8883b97d09d1ff2950a2ef8f AS hafah

FROM ${BASE_IMAGE}

USER root

RUN pip install --no-cache-dir --root-user-action=ignore \
        psycopg2-binary \
        "git+https://gitlab.syncad.com/hive/tests_api.git"

COPY --from=hafah /home/hafah_user/app /opt/hafah

ENV HOME=/tmp
ENTRYPOINT []
CMD ["bash"]
