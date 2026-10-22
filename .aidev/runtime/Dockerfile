# The image AIDEV runs this project's checks in (`environment.image` in
# .aidev/project.yaml). Checks run with the caller's uid and, for the slots that
# reach the shared HAF, on the per-run network its relay is on; every tool is in
# the image, nothing is installed at run time:
#
#   python:3.14-alpine (hive/tests_api requires Python >= 3.14)
#   + the postgrest binary of postgrest/postgrest:v16.4 (what CI's
#     docker/docker-compose-test.yml runs as `latest` today)
#   + bash, git, psql, shellcheck from Alpine's repository
#   + tavern, pytest and pytest-xdist, and hive/tests_api (validate_response, the tavern
#     tests' comparator) at TESTS_API_COMMIT
#   + psycopg2 (tests/regression/load_expected_data.py)
#   + HAfAH's SQL sources at /opt/hafah, from the HAfAH image CI's
#     docker/docker-compose.yml installs (HAFAH_REGISTRY/HAFAH_VERSION in
#     .gitlab-ci.yml, HAfAH fe9aaf53): haf_block_explorer's SQL calls hafah_backend
#   + sqlfluff 2.1.4, the version of CI's lint_sql_scripts (click < 8.2: sqlfluff
#     2.1.4 fails with a ValueError on newer click)
#
# Build and pin it with .aidev/runtime/build.sh; see .aidev/README.md.
FROM postgrest/postgrest:v16.4@sha256:d155c6718ed9a9f990d159a2ab7c0a3f16944dbb6d0a0344557421042acfe0df AS postgrest

# HAFAH_VERSION in .gitlab-ci.yml; move both together.
FROM registry.gitlab.syncad.com/hive/hafah@sha256:71cf4c7c2ca9f43e89047ee98a87659adeb0b4db52c00a88a34a540f9c40a9f2 AS hafah

FROM python:3.14-alpine@sha256:601e99e090cb08c2784a42395487709500bc39930307fe72f3f11a8f3c430762

ARG TESTS_API_COMMIT=455898cc3462d4e5ee2274756e5e3d44688fe204

RUN apk add --no-cache bash git postgresql-client shellcheck

RUN pip install --no-cache-dir --root-user-action=ignore \
        tavern==3.7.0 \
        pytest==9.1.1 \
        pytest-xdist==3.8.0 \
        psycopg2-binary==2.9.11 \
        sqlfluff==2.1.4 \
        click==8.1.6 \
        "https://gitlab.syncad.com/hive/tests_api/-/archive/${TESTS_API_COMMIT}/tests_api-${TESTS_API_COMMIT}.tar.gz"

COPY --from=postgrest /bin/postgrest /usr/local/bin/postgrest
COPY --from=hafah /home/hafah_user/app /opt/hafah

ENV HOME=/tmp
ENTRYPOINT []
CMD ["bash"]
