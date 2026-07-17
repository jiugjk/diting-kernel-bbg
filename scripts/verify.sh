#!/usr/bin/env bash
# Basic post-build verification (no device required).
# Usage: verify.sh <dist_dir> [out_dir]
set -euo pipefail

DIST_DIR="${1:-}"
OUT_DIR="${2:-}"

if [[ -z "${DIST_DIR}" || ! -d "${DIST_DIR}" ]]; then
  echo "Usage: $0 <dist_dir> [out_dir]" >&2
  exit 2
fi

pass=0
fail=0
warn=0
check() {
  local name="$1"; shift
  if "$@"; then
    echo "[PASS] ${name}"
    pass=$((pass+1))
  else
    echo "[FAIL] ${name}"
    fail=$((fail+1))
  fi
}
note() {
  echo "[WARN] $*"
  warn=$((warn+1))
}

echo "======== verification ========"

# 1) Image exists and is arm64 Image
if [[ -f "${DIST_DIR}/boot/Image" ]]; then
  check "Image exists" test -s "${DIST_DIR}/boot/Image"
  if command -v file >/dev/null 2>&1; then
    file "${DIST_DIR}/boot/Image" | tee /tmp/image.file.txt
    if grep -qiE 'Linux kernel.*ARM64|MS-DOS executable|data' /tmp/image.file.txt; then
      # ARM64 uncompressed Image often reported as "MS-DOS executable" or "data"
      check "Image file(1) readable" true
    else
      note "unexpected file(1) for Image: $(cat /tmp/image.file.txt)"
    fi
  fi
  # ARM64 Image magic at offset 0x38: "ARM\x64"
  magic="$(dd if="${DIST_DIR}/boot/Image" bs=1 skip=56 count=4 2>/dev/null | od -An -tx1 | tr -d ' \n')"
  if [[ "${magic}" == "41524d64" ]]; then
    check "Image ARM64 magic (ARM\\x64 @0x38)" true
  else
    # Some trees gzip-only; still record
    note "ARM64 magic not found (got ${magic:-none}); if Image is compressed or nonstandard, check manually"
  fi
else
  check "Image exists" false
fi

# 2) final.config contains BBG options
CFG="${DIST_DIR}/config/final.config"
if [[ -f "${CFG}" ]]; then
  check "CONFIG_BBG=y" grep -q '^CONFIG_BBG=y$' "${CFG}"
  check "CONFIG_BBG_BLOCK_BOOT=y" grep -q '^CONFIG_BBG_BLOCK_BOOT=y$' "${CFG}"
  check "CONFIG_BBG_BLOCK_RECOVERY=y" grep -q '^CONFIG_BBG_BLOCK_RECOVERY=y$' "${CFG}"
  check "CONFIG_LSM contains baseband_guard" grep -qE '^CONFIG_LSM=.*baseband_guard' "${CFG}"
  check "CONFIG_SECURITY=y" grep -q '^CONFIG_SECURITY=y$' "${CFG}"
  echo "---- BBG-related config ----"
  grep -E 'CONFIG_BBG|CONFIG_LSM|CONFIG_SECURITY=' "${CFG}" || true
else
  check "final.config present" false
fi

# 3) modules tarball
if [[ -f "${DIST_DIR}/modules/modules.tar.gz" ]]; then
  check "modules.tar.gz non-empty" test -s "${DIST_DIR}/modules/modules.tar.gz"
else
  note "modules.tar.gz not produced"
fi

# 4) unresolved symbols if Module.symvers / modpost log available
if [[ -n "${OUT_DIR:-}" && -d "${OUT_DIR}" ]]; then
  if [[ -f "${OUT_DIR}/Module.symvers" ]]; then
    check "Module.symvers exists" test -s "${OUT_DIR}/Module.symvers"
  fi
  # scan build logs if present
  if compgen -G "${OUT_DIR}/../logs/*.log" > /dev/null 2>&1; then
    if grep -R "undefined symbol" "${OUT_DIR}/../logs" >/dev/null 2>&1; then
      check "no undefined symbol in logs" false
    else
      check "no undefined symbol in logs" true
    fi
  fi
fi

# 5) SHA256SUMS present
check "SHA256SUMS.txt present" test -s "${DIST_DIR}/SHA256SUMS.txt"

echo "======== summary: pass=${pass} fail=${fail} warn=${warn} ========"
if [[ "${fail}" -gt 0 ]]; then
  exit 1
fi
exit 0
