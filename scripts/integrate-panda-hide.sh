#!/usr/bin/env bash
# Integrate in-tree panda-hide into a kernel source tree (idempotent).
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
if [[ ! -d "${SRC_DIR}" ]]; then
  echo "[ERROR] missing ${SRC_DIR}" >&2
  exit 1
fi

KERNEL_SRC="$(cd "${KERNEL_SRC}" && pwd)"
cd "${KERNEL_SRC}"

if [[ ! -d security || ! -f security/Makefile || ! -f security/Kconfig ]]; then
  echo "[ERROR] not a kernel tree with security/" >&2
  exit 1
fi

DEST="${KERNEL_SRC}/security/panda-hide"
echo "[+] Installing panda-hide sources -> ${DEST}"
rm -rf "${DEST}"
mkdir -p "${DEST}"
# Copy only build inputs (not HOOK_MAP.md required for build, but keep it)
cp -a "${SRC_DIR}/." "${DEST}/"

# Makefile entry
if ! grep -q 'panda-hide' security/Makefile; then
  printf '\nobj-$(CONFIG_PANDA_HIDE) += panda-hide/\n' >> security/Makefile
  echo "[+] security/Makefile updated"
fi

# Kconfig source (before last endmenu)
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

# Ensure KPROBES is available for this feature — do not force-enable here if
# platform disables it; fragment will request it and olddefconfig resolves.

mkdir -p "${KERNEL_SRC}/.panda-hide-integration"
{
  echo "source_dir=${SRC_DIR}"
  echo "dest_dir=security/panda-hide"
  echo "upstream=https://github.com/P4nda0s/kpm-panda-hide"
  echo "port=in-tree kprobe+LSM (no KernelPatch)"
  echo "integrated_at_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "${KERNEL_SRC}/.panda-hide-integration/info.txt"

echo "[+] panda-hide integrated"
echo "    Remember CONFIG_PANDA_HIDE=y and CONFIG_LSM includes panda_hide"
