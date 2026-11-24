#!/usr/bin/env bash
# `psql` for scripts/install_app.sh (and the btracker/reptracker installers it runs)
# under .aidev/shape-apply.sh: runs one psql call
# of the install through $AIDEV_DB_SHAPE_PSQL, a psql on the shape server that reads
# SQL on stdin (a -f path would resolve inside that server). The call's -c commands
# and -f files become its input in their order, each file's last statement ended
# at its end as psql ends it; with neither, its own stdin is.
# --single-transaction wraps that input in BEGIN and COMMIT, as psql wraps its -c
# and -f: with ON_ERROR_STOP an error ends the session before the COMMIT, so the
# call commits all of it or nothing.
# The connection argument is ignored, and any option install_app.sh does not use
# is refused rather than guessed at.
set -euo pipefail

# AIDEV_DB_SHAPE_PSQL is shell-quoted by aidev (shlex.join): parse it back as such.
shape_psql=()
eval "shape_psql=($AIDEV_DB_SHAPE_PSQL)"

sources=()
single=0
while [ $# -gt 0 ]; do
    case "$1" in
        -v) shift ;;
        -c) sources+=("c" "$2"); shift ;;
        -f) sources+=("f" "$2"); shift ;;
        --single-transaction) single=1 ;;
        -*) echo "shape-psql.sh: unsupported psql option $1" >&2; exit 2 ;;
        *) ;;
    esac
    shift
done

if [ ${#sources[@]} -eq 0 ]; then
    if [ "$single" = 1 ]; then
        # psql itself refuses it without -c or -f.
        echo "shape-psql.sh: --single-transaction needs -c or -f" >&2
        exit 2
    fi
    exec "${shape_psql[@]}" -v ON_ERROR_STOP=1
fi

{
    if [ "$single" = 1 ]; then
        printf 'BEGIN;\n'
    fi
    for ((i = 0; i < ${#sources[@]}; i += 2)); do
        if [ "${sources[i]}" = c ]; then
            printf '%s;\n' "${sources[i + 1]}"
        else
            # psql runs a file's last statement at the end of the file even without
            # a semicolon: end it there too (an empty statement otherwise).
            cat "${sources[i + 1]}"
            printf '\n;\n'
        fi
    done
    if [ "$single" = 1 ]; then
        printf 'COMMIT;\n'
    fi
} | "${shape_psql[@]}" -v ON_ERROR_STOP=1
