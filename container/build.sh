#!/usr/bin/env bash
#
# WP7 Part C -- build sbank-igwn.sif from container/sbank-igwn.def.
#
# MUST run on a Linux host with Apptainer installed (this repo's own dev
# checkout has no docker/apptainer, per .claude-wp/WP7.md -- this script is
# syntactically checked but has NOT been executed as part of this WP; build
# and smoke-test it on a cluster/CI linux box before trusting the .sif).
# `%files` paths in sbank-igwn.def (bin, sbank, setup.py, ...) are resolved
# relative to the CURRENT WORKING DIRECTORY at build time (an Apptainer
# convention -- NOT relative to the .def file's own location), so this
# script always cd's to the repo root first.
#
# Usage:
#   container/build.sh [output.sif]
#
# Requires: apptainer (or singularity) on PATH, network access to pull the
# condaforge/miniforge3 docker base image and conda-forge/pyseobnr's conda
# packages, and (per the recipe) enough local disk for the build -- see
# README.md "image-size expectations".

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DEF_FILE="container/sbank-igwn.def"
OUT_SIF="${1:-container/sbank-igwn.sif}"

BUILD_CMD=""
if command -v apptainer >/dev/null 2>&1; then
    BUILD_CMD="apptainer"
elif command -v singularity >/dev/null 2>&1; then
    BUILD_CMD="singularity"
else
    echo "build.sh: neither 'apptainer' nor 'singularity' found on PATH." >&2
    echo "  Install Apptainer (https://apptainer.org/) on a Linux build host, then rerun." >&2
    exit 1
fi

cd "${REPO_ROOT}"

echo "build.sh: building ${OUT_SIF} from ${DEF_FILE} (cwd=${REPO_ROOT}, builder=${BUILD_CMD})"
"${BUILD_CMD}" build --fakeroot "${OUT_SIF}" "${DEF_FILE}"

echo "build.sh: done. Next steps (see README.md 'Distribution via OSDF'):"
echo "  1. Smoke-test:   ${BUILD_CMD} exec ${OUT_SIF} sbank_sim --help"
echo "  2. Smoke-test:   ${BUILD_CMD} exec ${OUT_SIF} ligolw_no_ilwdchar --help"
echo "  3. Copy the .sif to OSDF and point condor's container_image / +SingularityImage"
echo "     at the resulting osdf:// URL (README.md has the exact submit-file snippet;"
echo "     configs/*.yaml's condor.container_image field is where a generated campaign"
echo "     DAG picks this up)."
