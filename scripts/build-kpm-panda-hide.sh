#!/usr/bin/env bash
# Build panda-hide as a KernelPatch KPM (NOT an in-tree kernel module).
# Project requirement: aarch64-none-elf- + KernelPatch headers.
# Output: dist/kpm/panda-hide.kpm
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
WORK_DIR="${WORK_DIR:-${REPO_ROOT}/work}"
DIST_DIR="${DIST_DIR:-${WORK_DIR}/dist}"
KPM_DIR="${WORK_DIR}/kpm-panda-hide"
KP_DIR="${WORK_DIR}/KernelPatch"
TOOLCHAIN_DIR="${WORK_DIR}/aarch64-none-elf"
TARGET_COMPILE="${TARGET_COMPILE:-${TOOLCHAIN_DIR}/bin/aarch64-none-elf-}"

log() { echo "[$(date -u +%H:%M:%S)] $*"; }
die() { echo "[ERROR] $*" >&2; exit 1; }

mkdir -p "${WORK_DIR}" "${DIST_DIR}/kpm" "${DIST_DIR}/meta"

if [[ ! -x "${TARGET_COMPILE}gcc" ]]; then
  log "Fetching aarch64-none-elf toolchain (Arm GNU)"
  mkdir -p "${TOOLCHAIN_DIR}"
  # Use a commonly mirrored release; override TOOLCHAIN_URL if needed.
  TOOLCHAIN_URL="${TOOLCHAIN_URL:-https://developer.arm.com/-/media/Files/downloads/gnu/13.2.rel1/binrel/arm-gnu-toolchain-13.2.rel1-x86_64-aarch64-none-elf.tar.xz}"
  tmp="$(mktemp -d)"
  if ! curl -fL --retry 3 "${TOOLCHAIN_URL}" -o "${tmp}/tc.tar.xz"; then
    die "failed to download aarch64-none-elf toolchain; set TOOLCHAIN_URL or TARGET_COMPILE"
  fi
  tar -xJf "${tmp}/tc.tar.xz" -C "${tmp}"
  src="$(find "${tmp}" -maxdepth 1 -type d -name 'arm-gnu-toolchain-*' | head -n1)"
  [[ -n "${src}" ]] || die "toolchain archive layout unexpected"
  rm -rf "${TOOLCHAIN_DIR}"
  mv "${src}" "${TOOLCHAIN_DIR}"
  TARGET_COMPILE="${TOOLCHAIN_DIR}/bin/aarch64-none-elf-"
fi
[[ -x "${TARGET_COMPILE}gcc" ]] || die "gcc missing: ${TARGET_COMPILE}gcc"

if [[ ! -d "${KP_DIR}/.git" ]]; then
  log "Cloning KernelPatch"
  git clone --depth=1 https://github.com/bmax121/KernelPatch.git "${KP_DIR}"
fi
if [[ ! -d "${KPM_DIR}/.git" ]]; then
  log "Cloning kpm-panda-hide"
  git clone --depth=1 https://github.com/P4nda0s/kpm-panda-hide.git "${KPM_DIR}"
  git -C "${KPM_DIR}" submodule update --init --recursive || true
fi

log "Building panda-hide.kpm"
make -C "${KPM_DIR}" clean || true
make -C "${KPM_DIR}" TARGET_COMPILE="${TARGET_COMPILE}" KP_DIR="${KP_DIR}"

[[ -f "${KPM_DIR}/panda-hide.kpm" ]] || die "panda-hide.kpm not produced"
cp -f "${KPM_DIR}/panda-hide.kpm" "${DIST_DIR}/kpm/panda-hide.kpm"
sha256sum "${DIST_DIR}/kpm/panda-hide.kpm" | tee "${DIST_DIR}/meta/panda-hide.sha256"

{
  echo "kpm_repo=https://github.com/P4nda0s/kpm-panda-hide"
  echo "kpm_sha=$(git -C "${KPM_DIR}" rev-parse HEAD)"
  echo "kernelpatch_sha=$(git -C "${KP_DIR}" rev-parse HEAD)"
  echo "note=This is a KernelPatch KPM, not an in-tree kernel integration."
  echo "load_requires=KernelPatch/APatch environment on device"
} > "${DIST_DIR}/meta/kpm-panda-hide.txt"

log "KPM artifact: ${DIST_DIR}/kpm/panda-hide.kpm"
