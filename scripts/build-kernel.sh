#!/usr/bin/env bash
# Build Xiaomi diting (bsp-diting-s-oss) kernel with Baseband-guard for GitHub Actions / Linux hosts.
# Single-tree (non-mixed) build based on official build.config.* facts:
#   - BRANCH=android12-5.10, KMI_GENERATION=9
#   - LLVM + clang-r416183b
#   - DEFCONFIG base: gki_defconfig + vendor/diting_GKI.config (+ consolidate optional)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# ---------------- defaults (override via env) ----------------
WORK_DIR="${WORK_DIR:-${REPO_ROOT}/work}"
KERNEL_REPO="${KERNEL_REPO:-https://github.com/MiCode/Xiaomi_Kernel_OpenSource.git}"
KERNEL_BRANCH="${KERNEL_BRANCH:-bsp-diting-s-oss}"
KERNEL_SRC="${KERNEL_SRC:-${WORK_DIR}/kernel}"
OUT_DIR="${OUT_DIR:-${WORK_DIR}/out}"
DIST_DIR="${DIST_DIR:-${WORK_DIR}/dist}"
CLANG_DIR="${CLANG_DIR:-${WORK_DIR}/clang-r416183b}"
VARIANT="${VARIANT:-consolidate}"   # consolidate | gki
BBG_REF="${BBG_REF:-main}"
JOBS="${JOBS:-$(nproc)}"
SKIP_CLONE="${SKIP_CLONE:-0}"
SKIP_TOOLCHAIN="${SKIP_TOOLCHAIN:-0}"
LOCALVERSION_OVERRIDE="${LOCALVERSION_OVERRIDE:--android12-9-bbg}"
# Match stock fingerprint style if user wants; default keeps OSS identity + bbg tag.
KBUILD_BUILD_USER="${KBUILD_BUILD_USER:-bbg-ci}"
KBUILD_BUILD_HOST="${KBUILD_BUILD_HOST:-github-actions}"
# Stock string was: #1 SMP PREEMPT Tue Oct 21 03:03:12 UTC 2025 — we do not forge dates.
export KBUILD_BUILD_TIMESTAMP="${KBUILD_BUILD_TIMESTAMP:-$(date -u)}"
export KBUILD_BUILD_USER KBUILD_BUILD_HOST

log() { echo "[$(date -u +%H:%M:%S)] $*"; }
die() { echo "[ERROR] $*" >&2; exit 1; }

need_cmd() { command -v "$1" >/dev/null 2>&1 || die "missing command: $1"; }

fetch_clang() {
  if [[ -x "${CLANG_DIR}/bin/clang" ]]; then
    log "Clang already present: ${CLANG_DIR}"
    "${CLANG_DIR}/bin/clang" --version | head -n1
    return
  fi
  log "Downloading Android Clang r416183b (matches official build.config.common)"
  mkdir -p "${CLANG_DIR}"
  local url candidates
  candidates=(
    "https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/android12-release/clang-r416183b.tar.gz"
    "https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/master/clang-r416183b.tar.gz"
  )
  local ok=0
  for url in "${candidates[@]}"; do
    log "try: ${url}"
    if curl -fL --retry 3 --retry-delay 2 "${url}" | tar -xz -C "${CLANG_DIR}"; then
      ok=1
      break
    fi
  done
  # Some mirrors extract into clang-r416183b/ subdir
  if [[ ! -x "${CLANG_DIR}/bin/clang" ]]; then
    if [[ -x "${CLANG_DIR}/clang-r416183b/bin/clang" ]]; then
      CLANG_DIR="${CLANG_DIR}/clang-r416183b"
    else
      # nested single top dir
      local sub
      sub="$(find "${CLANG_DIR}" -maxdepth 2 -type f -path '*/bin/clang' 2>/dev/null | head -n1 || true)"
      if [[ -n "${sub}" ]]; then
        CLANG_DIR="$(cd "$(dirname "${sub}")/.." && pwd)"
      fi
    fi
  fi
  [[ -x "${CLANG_DIR}/bin/clang" ]] || die "clang not found after download"
  "${CLANG_DIR}/bin/clang" --version | head -n1
}

clone_kernel() {
  if [[ "${SKIP_CLONE}" == "1" && -d "${KERNEL_SRC}/.git" ]]; then
    log "SKIP_CLONE=1, reusing ${KERNEL_SRC}"
  else
    log "Cloning ${KERNEL_REPO} @ ${KERNEL_BRANCH}"
    rm -rf "${KERNEL_SRC}"
    git clone --depth=1 --branch "${KERNEL_BRANCH}" "${KERNEL_REPO}" "${KERNEL_SRC}"
  fi
  KERNEL_SHA="$(git -C "${KERNEL_SRC}" rev-parse HEAD)"
  log "Kernel SHA: ${KERNEL_SHA}"
  # Record version files if present
  if [[ -f "${KERNEL_SRC}/Makefile" ]]; then
    grep -E '^VERSION|^PATCHLEVEL|^SUBLEVEL|^EXTRAVERSION' "${KERNEL_SRC}/Makefile" || true
  fi
}

prepare_defconfig() {
  log "Preparing defconfig (variant=${VARIANT})"
  mkdir -p "${OUT_DIR}"
  local make_common=(
    make -C "${KERNEL_SRC}" O="${OUT_DIR}"
    ARCH=arm64
    LLVM=1
    LLVM_IAS=1
    CC=clang
    LD=ld.lld
    AR=llvm-ar
    NM=llvm-nm
    STRIP=llvm-strip
    OBJCOPY=llvm-objcopy
    OBJDUMP=llvm-objdump
    READELF=llvm-readelf
    HOSTCC=clang
    HOSTCXX=clang++
    HOSTLD=ld.lld
  )

  # Base GKI defconfig from tree
  "${make_common[@]}" gki_defconfig

  # Merge official vendor fragments (from build.config.msm.gki logic)
  local fragments=()
  fragments+=("${KERNEL_SRC}/arch/arm64/configs/vendor/diting_GKI.config")
  if [[ "${VARIANT}" == "consolidate" ]]; then
    if [[ -f "${KERNEL_SRC}/arch/arm64/configs/consolidate.fragment" ]]; then
      fragments+=("${KERNEL_SRC}/arch/arm64/configs/consolidate.fragment")
    fi
    if [[ -f "${KERNEL_SRC}/arch/arm64/configs/vendor/diting_consolidate.config" ]]; then
      fragments+=("${KERNEL_SRC}/arch/arm64/configs/vendor/diting_consolidate.config")
    fi
  fi

  local args=("${OUT_DIR}/.config")
  for f in "${fragments[@]}"; do
    [[ -f "${f}" ]] || die "missing fragment: ${f}"
    args+=("${f}")
    log "  fragment: ${f}"
  done
  (
    cd "${KERNEL_SRC}"
    ARCH=arm64 ./scripts/kconfig/merge_config.sh -m -O "${OUT_DIR}" "${args[@]}"
  )

  # Optional DT overlay support as official build enables it for diting
  if [[ -x "${KERNEL_SRC}/scripts/config" ]]; then
    "${KERNEL_SRC}/scripts/config" --file "${OUT_DIR}/.config" -e BUILD_ARM64_DT_OVERLAY || true
  fi

  # Apply BBG fragment + LSM
  bash "${SCRIPT_DIR}/apply-bbg-config.sh" "${KERNEL_SRC}" "${OUT_DIR}" "${REPO_ROOT}/config/bbg.fragment"

  # Localversion
  if [[ -n "${LOCALVERSION_OVERRIDE}" ]]; then
    "${KERNEL_SRC}/scripts/config" --file "${OUT_DIR}/.config" --set-str LOCALVERSION "${LOCALVERSION_OVERRIDE}" || true
  fi

  "${make_common[@]}" olddefconfig
}

build_all() {
  log "Building Image/modules/dtbs with -j${JOBS}"
  local make_common=(
    make -C "${KERNEL_SRC}" O="${OUT_DIR}"
    ARCH=arm64
    LLVM=1
    LLVM_IAS=1
    CC=clang
    LD=ld.lld
    AR=llvm-ar
    NM=llvm-nm
    STRIP=llvm-strip
    OBJCOPY=llvm-objcopy
    OBJDUMP=llvm-objdump
    READELF=llvm-readelf
    HOSTCC=clang
    HOSTCXX=clang++
    HOSTLD=ld.lld
    -j"${JOBS}"
  )
  # Primary targets used by official build.config.aarch64 / msm.common
  "${make_common[@]}" Image modules dtbs
}

package_dist() {
  log "Packaging dist to ${DIST_DIR}"
  rm -rf "${DIST_DIR}"
  mkdir -p "${DIST_DIR}"/{boot,modules,config,meta,dtb}

  # Kernel image
  if [[ -f "${OUT_DIR}/arch/arm64/boot/Image" ]]; then
    cp -f "${OUT_DIR}/arch/arm64/boot/Image" "${DIST_DIR}/boot/Image"
  fi
  if [[ -f "${OUT_DIR}/arch/arm64/boot/Image.gz" ]]; then
    cp -f "${OUT_DIR}/arch/arm64/boot/Image.gz" "${DIST_DIR}/boot/Image.gz"
  elif [[ -f "${DIST_DIR}/boot/Image" ]]; then
    gzip -c -9 "${DIST_DIR}/boot/Image" > "${DIST_DIR}/boot/Image.gz"
  fi

  # DTBs / DTBOs if present
  find "${OUT_DIR}/arch/arm64/boot/dts" -type f \( -name '*.dtb' -o -name '*.dtbo' \) \
    -exec cp -t "${DIST_DIR}/dtb/" {} + 2>/dev/null || true

  # Modules (install into staging)
  local mod_stage="${WORK_DIR}/modules_staging"
  rm -rf "${mod_stage}"
  mkdir -p "${mod_stage}"
  make -C "${KERNEL_SRC}" O="${OUT_DIR}" \
    ARCH=arm64 LLVM=1 LLVM_IAS=1 CC=clang LD=ld.lld \
    INSTALL_MOD_PATH="${mod_stage}" modules_install
  if [[ -d "${mod_stage}/lib/modules" ]]; then
    tar -C "${mod_stage}" -I 'gzip -9' -cf "${DIST_DIR}/modules/modules.tar.gz" lib/modules
  fi

  # Configs / metadata
  cp -f "${OUT_DIR}/.config" "${DIST_DIR}/config/final.config"
  if [[ -f "${KERNEL_SRC}/.bbg-integration/info.txt" ]]; then
    cp -f "${KERNEL_SRC}/.bbg-integration/info.txt" "${DIST_DIR}/meta/bbg-integration.txt"
  fi

  {
    echo "kernel_repo=${KERNEL_REPO}"
    echo "kernel_branch=${KERNEL_BRANCH}"
    echo "kernel_sha=${KERNEL_SHA:-unknown}"
    echo "variant=${VARIANT}"
    echo "clang_dir=${CLANG_DIR}"
    echo "clang_version=$("${CLANG_DIR}/bin/clang" --version | head -n1)"
    echo "localversion=${LOCALVERSION_OVERRIDE}"
    echo "build_user=${KBUILD_BUILD_USER}"
    echo "build_host=${KBUILD_BUILD_HOST}"
    echo "build_timestamp=${KBUILD_BUILD_TIMESTAMP}"
    echo "jobs=${JOBS}"
  } > "${DIST_DIR}/meta/build-info.txt"

  # SHA256 sums for real artifacts only
  (
    cd "${DIST_DIR}"
    find . -type f ! -name 'SHA256SUMS.txt' -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS.txt
  )

  log "Artifacts:"
  find "${DIST_DIR}" -type f -printf '%s\t%p\n' | sort -k2
}

verify_inline() {
  bash "${SCRIPT_DIR}/verify.sh" "${DIST_DIR}" "${OUT_DIR}" || true
}

# ---------------- main ----------------
need_cmd git
need_cmd curl
need_cmd make
need_cmd tar
need_cmd gzip
need_cmd python3

mkdir -p "${WORK_DIR}"
export PATH="${CLANG_DIR}/bin:${PATH}"

if [[ "${SKIP_TOOLCHAIN}" != "1" ]]; then
  fetch_clang
  export PATH="${CLANG_DIR}/bin:${PATH}"
fi
need_cmd clang
need_cmd ld.lld

clone_kernel
bash "${SCRIPT_DIR}/integrate-bbg.sh" "${KERNEL_SRC}" "${BBG_REF}"
prepare_defconfig
build_all
package_dist
verify_inline

log "DONE. Dist: ${DIST_DIR}"
