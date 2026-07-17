#!/usr/bin/env bash
# Merge security fragments (BBG + panda-hide) and normalize CONFIG_LSM.
# Usage: apply-bbg-config.sh <kernel_src> <out_dir>
set -euo pipefail

KERNEL_SRC="${1:-}"
OUT_DIR="${2:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

if [[ -z "${KERNEL_SRC}" || -z "${OUT_DIR}" ]]; then
  echo "Usage: $0 <kernel_src> <out_dir>" >&2
  exit 2
fi

KERNEL_SRC="$(cd "${KERNEL_SRC}" && pwd)"
OUT_DIR="$(cd "${OUT_DIR}" && pwd)"
CFG="${OUT_DIR}/.config"

if [[ ! -f "${CFG}" ]]; then
  echo "[ERROR] missing ${CFG}; run defconfig first" >&2
  exit 1
fi

apply_fragment() {
  local frag="$1"
  [[ -f "${frag}" ]] || { echo "[ERROR] missing ${frag}" >&2; exit 1; }
  echo "[+] Applying fragment: ${frag}"
  if [[ -x "${KERNEL_SRC}/scripts/kconfig/merge_config.sh" ]]; then
    (
      cd "${KERNEL_SRC}"
      ARCH=arm64 ./scripts/kconfig/merge_config.sh -m -O "${OUT_DIR}" "${CFG}" "${frag}"
    )
  else
    while IFS= read -r line || [[ -n "${line}" ]]; do
      [[ -z "${line}" || "${line}" =~ ^# ]] && continue
      key="${line%%=*}"
      sed -i "/^${key}=/d;/^# ${key} is not set/d" "${CFG}"
      echo "${line}" >> "${CFG}"
    done < "${frag}"
  fi
}

apply_fragment "${REPO_ROOT}/config/bbg.fragment"
apply_fragment "${REPO_ROOT}/config/panda-hide.fragment"

# Normalize CONFIG_LSM: keep existing list, append required LSMs.
current_lsm="$(grep -E '^CONFIG_LSM=' "${CFG}" | head -n1 | cut -d= -f2- | tr -d '"' || true)"
if [[ -z "${current_lsm}" ]]; then
  current_lsm="lockdown,yama,loadpin,safesetid,integrity,selinux,bpf"
fi
for lsm in baseband_guard panda_hide; do
  if [[ ",${current_lsm}," != *",${lsm},"* ]]; then
    current_lsm="${current_lsm},${lsm}"
  fi
done
sed -i '/^CONFIG_LSM=/d' "${CFG}"
echo "CONFIG_LSM=\"${current_lsm}\"" >> "${CFG}"

# Force BBG options
for opt in CONFIG_BBG CONFIG_BBG_BLOCK_BOOT CONFIG_BBG_BLOCK_RECOVERY; do
  sed -i "/^${opt}=/d;/^# ${opt} is not set/d" "${CFG}"
  echo "${opt}=y" >> "${CFG}"
done

# Force panda-hide + deps
for opt in CONFIG_SECURITY CONFIG_KPROBES CONFIG_KALLSYMS CONFIG_PANDA_HIDE; do
  sed -i "/^${opt}=/d;/^# ${opt} is not set/d" "${CFG}"
  echo "${opt}=y" >> "${CFG}"
done
# KALLSYMS_ALL is nice-to-have
if ! grep -q '^CONFIG_KALLSYMS_ALL=y$' "${CFG}"; then
  sed -i '/^# CONFIG_KALLSYMS_ALL is not set/d;/^CONFIG_KALLSYMS_ALL=/d' "${CFG}"
  echo "CONFIG_KALLSYMS_ALL=y" >> "${CFG}"
fi

echo "[+] Security config applied"
echo "    CONFIG_BBG=y BLOCK_BOOT=y BLOCK_RECOVERY=y"
echo "    CONFIG_PANDA_HIDE=y CONFIG_KPROBES=y"
echo "    CONFIG_LSM=\"${current_lsm}\""
