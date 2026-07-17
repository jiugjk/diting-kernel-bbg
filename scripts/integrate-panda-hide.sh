#!/usr/bin/env bash
# Integrate in-tree panda-hide + apply zero-kprobe static patches.
# Usage: integrate-panda-hide.sh <kernel_src>
set -euo pipefail

KERNEL_SRC="${1:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SRC_DIR="${REPO_ROOT}/panda-hide-in-tree"

if [[ -z "${KERNEL_SRC}" || ! -d "${KERNEL_SRC}" ]]; then
  echo "Usage: $0 <kernel_src>" >&2
  exit 2
fi
KERNEL_SRC="$(cd "${KERNEL_SRC}" && pwd)"
cd "${KERNEL_SRC}"

[[ -d security && -f security/Makefile && -f security/Kconfig ]] || {
  echo "[ERROR] not a kernel tree with security/" >&2
  exit 1
}

DEST="${KERNEL_SRC}/security/panda-hide"
echo "[+] Installing panda-hide -> ${DEST}"
rm -rf "${DEST}"
mkdir -p "${DEST}"
# copy C sources / Kbuild (not the nested include tree as-is)
cp -a "${SRC_DIR}/." "${DEST}/"
rm -rf "${DEST}/include" 2>/dev/null || true

# Install public header
mkdir -p "${KERNEL_SRC}/include/linux"
cp -f "${SRC_DIR}/include/linux/panda_hide.h" "${KERNEL_SRC}/include/linux/panda_hide.h"
echo "[+] installed include/linux/panda_hide.h"

# Makefile / Kconfig wiring
if ! grep -q 'panda-hide' security/Makefile; then
  printf '\nobj-$(CONFIG_PANDA_HIDE) += panda-hide/\n' >> security/Makefile
  echo "[+] security/Makefile updated"
fi
if ! grep -q 'security/panda-hide/Kconfig' security/Kconfig; then
  if grep -q '^endmenu[[:space:]]*$' security/Kconfig; then
    awk '
      { a[NR]=$0 }
      END {
        last=0
        for (i=1;i<=NR;i++) if (a[i] ~ /^endmenu[[:space:]]*$/) last=i
        for (i=1;i<=NR;i++) {
          if (i==last) print "source \"security/panda-hide/Kconfig\""
          print a[i]
        }
      }' security/Kconfig > security/Kconfig.tmp
    mv security/Kconfig.tmp security/Kconfig
  else
    printf '\nsource "security/panda-hide/Kconfig"\n' >> security/Kconfig
  fi
  echo "[+] security/Kconfig updated"
fi

# Zero-kprobe static call-site patches
echo "[+] Applying static patches (array.c / task_mmu.c / ...)"
python3 "${SCRIPT_DIR}/apply-panda-static.py" "${KERNEL_SRC}"

mkdir -p "${KERNEL_SRC}/.panda-hide-integration"
{
  echo "mode=static+lsm"
  echo "upstream=https://github.com/P4nda0s/kpm-panda-hide"
  echo "header=include/linux/panda_hide.h"
  echo "dir=security/panda-hide"
  echo "patched=fs/proc/array.c,fs/proc/base.c,fs/proc/task_mmu.c,fs/exec.c,fs/open.c,mm/memory.c"
  echo "integrated_at_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "${KERNEL_SRC}/.panda-hide-integration/info.txt"

echo "[+] panda-hide static integration complete"
