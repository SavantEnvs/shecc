# Commit-image Dockerfile (SMALL form) — builds ON TOP of the org C/C++ base image.
# shecc needs qemu-user (to run the ARM binaries it emits, for the bootstrap + test suite) and
# graphviz/jq are pulled in for parity with upstream tooling.
FROM ghcr.io/savantenvs/base:20260621

ARG COMMIT
ARG REPO_URL
ARG SOURCE_DATE_EPOCH
ARG SANITIZER_FLAGS
ARG MAYHEM_JOBS=

# Extra build/test dependencies: qemu-arm runs the ARM ELF binaries shecc emits (needed by the
# stage-2 bootstrap and the functional test suite).
USER root
RUN [ -n "$SOURCE_DATE_EPOCH" ] && repro-sources-list.sh || true ; \
    apt-get update && apt-get install -yq --no-install-recommends \
        qemu-user graphviz jq \
    && rm -rf /var/lib/apt/lists/*
USER mayhem

WORKDIR /mayhem
COPY --chown=2000:2000 . /mayhem

RUN bash mayhem/build.sh

RUN if [ -f mayhem/test.sh ]; then bash mayhem/test.sh; else echo "no mayhem/test.sh"; fi

LABEL org.opencontainers.image.source="${REPO_URL}" \
      org.opencontainers.image.revision="${COMMIT}" \
      rlenv.tier="commit" \
      rlenv.source_date_epoch="${SOURCE_DATE_EPOCH}" \
      rlenv.user="mayhem"

USER mayhem
WORKDIR /mayhem
