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
# Always apply on CI/default path: free runners OOM on FULL LTO
if [[ "${DISABLE_LTO:-1}" == "1" ]]; then
  apply_fragment "${REPO_ROOT}/config/ci-nolto.fragment"
fi

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

# Force panda-hide (static mode; kprobes optional)
for opt in CONFIG_SECURITY CONFIG_PANDA_HIDE CONFIG_PANDA_HIDE_STATIC; do
  sed -i "/^${opt}=/d;/^# ${opt} is not set/d" "${CFG}"
  echo "${opt}=y" >> "${CFG}"
done
# Explicitly disable kprobe backend unless user forced it
if ! grep -q '^CONFIG_PANDA_HIDE_KPROBES=y$' "${CFG}"; then
  sed -i '/^CONFIG_PANDA_HIDE_KPROBES=/d;/^# CONFIG_PANDA_HIDE_KPROBES is not set/d' "${CFG}"
  echo "# CONFIG_PANDA_HIDE_KPROBES is not set" >> "${CFG}"
fi

# Force LTO off for CI-sized machines (override gki_defconfig FULL LTO)
if [[ "${DISABLE_LTO:-1}" == "1" ]]; then
  for opt in CONFIG_LTO_CLANG_FULL CONFIG_LTO_CLANG_THIN CONFIG_CFI_CLANG CONFIG_CFI_PERMISSIVE CONFIG_CFI_CLANG_SHADOW; do
    sed -i "/^${opt}=/d;/^# ${opt} is not set/d" "${CFG}"
    echo "# ${opt} is not set" >> "${CFG}"
  done
  sed -i '/^CONFIG_LTO_NONE=/d;/^# CONFIG_LTO_NONE is not set/d' "${CFG}"
  echo "CONFIG_LTO_NONE=y" >> "${CFG}"
fi

echo "[+] Security config applied"
echo "    CONFIG_BBG=y BLOCK_BOOT=y BLOCK_RECOVERY=y"
echo "    CONFIG_PANDA_HIDE=y STATIC=y (kprobes off by default)"
if [[ "${DISABLE_LTO:-1}" == "1" ]]; then
  echo "    LTO/CFI disabled for CI (DISABLE_LTO=1)"
fi
echo "    CONFIG_LSM=\"${current_lsm}\""
