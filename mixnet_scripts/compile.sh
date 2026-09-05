#!/bin/bash
# Build mixnet-htsim. datacenter has no 'clean' target (only clos does) and needs FF_HOME for the
# FlatBuffers fbuf headers (mixnet-flexflow/fbuf/include). Override with FF_HOME=... if elsewhere.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"          # mixnet-htsim
CLOS_DIR="${REPO_ROOT}/src/clos"
DC_DIR="${CLOS_DIR}/datacenter"
FF_HOME="${FF_HOME:-${REPO_ROOT}/../mixnet-flexflow}"  # has fbuf/include
echo "FF_HOME=${FF_HOME}"
[ -d "${FF_HOME}/fbuf/include" ] || { echo "ERROR: ${FF_HOME}/fbuf/include not found; set FF_HOME"; exit 1; }
echo "[1/2] build clos (libhtsim.a)"
( cd "${CLOS_DIR}" && make -j )
echo "[2/2] build datacenter binaries"
( cd "${DC_DIR}" && make -j FF_HOME="${FF_HOME}" )
echo "Done -> ${DC_DIR}/htsim_tcp_*"
