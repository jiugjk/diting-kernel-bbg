#!/usr/bin/env bash
# Merge BBG fragment into an existing out/.config and normalize CONFIG_LSM.
# Usage: apply-bbg-config.sh <kernel_src> <out_dir> [fragment]
set -euo pipefail

KERNEL_SRC="${1:-}"
OUT_DIR="${2:-}"
FRAGMENT="${3:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

if [[ -z "${KERNEL_SRC}" || -z "${OUT_DIR}" ]]; then
  echo "Usage: $0 <kernel_src> <out_dir> [fragment]" >&2
  exit 2
fi

KERNEL_SRC="$(cd "${KERNEL_SRC}" && pwd)"
OUT_DIR="$(cd "${OUT_DIR}" && pwd)"
FRAGMENT="${FRAGMENT:-${REPO_ROOT}/config/bbg.fragment}"
CFG="${OUT_DIR}/.config"

if [[ ! -f "${CFG}" ]]; then
  echo "[ERROR] missing ${CFG}; run defconfig first" >&2
  exit 1
fi
if [[ ! -f "${FRAGMENT}" ]]; then
  echo "[ERROR] missing fragment ${FRAGMENT}" >&2
  exit 1
fi

echo "[+] Applying fragment: ${FRAGMENT}"
# merge_config.sh lives in kernel tree
if [[ -x "${KERNEL_SRC}/scripts/kconfig/merge_config.sh" ]]; then
  (
    cd "${KERNEL_SRC}"
    ARCH=arm64 ./scripts/kconfig/merge_config.sh -m -O "${OUT_DIR}" "${CFG}" "${FRAGMENT}"
  )
else
  # Fallback: append non-comment keys
  while IFS= read -r line || [[ -n "${line}" ]]; do
    [[ -z "${line}" || "${line}" =~ ^# ]] && continue
    key="${line%%=*}"
    sed -i "/^${key}=/d;/^# ${key} is not set/d" "${CFG}"
    echo "${line}" >> "${CFG}"
  done < "${FRAGMENT}"
fi

# Normalize CONFIG_LSM: keep existing list, append baseband_guard if missing.
current_lsm="$(grep -E '^CONFIG_LSM=' "${CFG}" | head -n1 | cut -d= -f2- | tr -d '"' || true)"
if [[ -z "${current_lsm}" ]]; then
  # sensible Android12/5.10 default order used by many GKI trees
  current_lsm="lockdown,yama,loadpin,safesetid,integrity,selinux,bpf"
fi
if [[ ",${current_lsm}," != *",baseband_guard,"* ]]; then
  current_lsm="${current_lsm},baseband_guard"
fi
sed -i '/^CONFIG_LSM=/d' "${CFG}"
echo "CONFIG_LSM=\"${current_lsm}\"" >> "${CFG}"

# Force BBG options explicitly (all optional protections requested by user)
for opt in CONFIG_BBG CONFIG_BBG_BLOCK_BOOT CONFIG_BBG_BLOCK_RECOVERY; do
  sed -i "/^${opt}=/d;/^# ${opt} is not set/d" "${CFG}"
  echo "${opt}=y" >> "${CFG}"
done
sed -i '/^# CONFIG_SECURITY is not set/d;/^CONFIG_SECURITY=/d' "${CFG}"
echo "CONFIG_SECURITY=y" >> "${CFG}"

echo "[+] BBG config applied"
echo "    CONFIG_BBG=y"
echo "    CONFIG_BBG_BLOCK_BOOT=y"
echo "    CONFIG_BBG_BLOCK_RECOVERY=y"
echo "    CONFIG_LSM=\"${current_lsm}\""
