#!/usr/bin/env bash
# Integrate Baseband-guard into a kernel tree (idempotent, reviewable).
# Usage: integrate-bbg.sh <kernel_src_dir> [bbg_ref]
set -euo pipefail

KERNEL_SRC="${1:-}"
BBG_REF="${2:-main}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

if [[ -z "${KERNEL_SRC}" || ! -d "${KERNEL_SRC}" ]]; then
  echo "Usage: $0 <kernel_src_dir> [bbg_ref]" >&2
  exit 2
fi

KERNEL_SRC="$(cd "${KERNEL_SRC}" && pwd)"
cd "${KERNEL_SRC}"

if [[ ! -d security || ! -f security/Makefile || ! -f security/Kconfig ]]; then
  echo "[ERROR] Not a kernel tree with security/: ${KERNEL_SRC}" >&2
  exit 1
fi

BBG_DIR="${KERNEL_SRC}/Baseband-guard"
BBG_REPO="${BBG_REPO:-https://github.com/vc-teahouse/Baseband-guard.git}"

echo "[+] Kernel: ${KERNEL_SRC}"
echo "[+] BBG ref: ${BBG_REF}"

if [[ -d "${BBG_DIR}/.git" ]]; then
  git -C "${BBG_DIR}" fetch --tags origin
  git -C "${BBG_DIR}" checkout -q "${BBG_REF}"
  git -C "${BBG_DIR}" pull --ff-only || true
else
  rm -rf "${BBG_DIR}"
  git clone --depth=1 --branch "${BBG_REF}" "${BBG_REPO}" "${BBG_DIR}" \
    || git clone --depth=1 "${BBG_REPO}" "${BBG_DIR}"
  if [[ "${BBG_REF}" != "main" && "${BBG_REF}" != "master" ]]; then
    git -C "${BBG_DIR}" fetch --depth=1 origin "${BBG_REF}" || true
    git -C "${BBG_DIR}" checkout -q "${BBG_REF}" || true
  fi
fi

BBG_SHA="$(git -C "${BBG_DIR}" rev-parse HEAD)"
echo "[+] Baseband-guard commit: ${BBG_SHA}"

# Prefer official setup.sh when present (creates symlink + Makefile/Kconfig wiring).
if [[ -x "${BBG_DIR}/setup.sh" || -f "${BBG_DIR}/setup.sh" ]]; then
  echo "[+] Running official setup.sh"
  # setup.sh expects to be run from kernel root and clones into ./Baseband-guard
  # We already have Baseband-guard; re-run setup for wiring only.
  bash "${BBG_DIR}/setup.sh" "${BBG_REF}" || bash "${BBG_DIR}/setup.sh"
else
  echo "[!] setup.sh missing; applying minimal wiring"
  ln -sfn ../Baseband-guard security/baseband-guard
  if ! grep -q 'baseband-guard' security/Makefile; then
    printf '\nobj-$(CONFIG_BBG) += baseband-guard/\n' >> security/Makefile
  fi
  if ! grep -q 'security/baseband-guard/Kconfig' security/Kconfig; then
    if grep -q '^endmenu[[:space:]]*$' security/Kconfig; then
      # insert before last endmenu
      awk '
        { a[NR]=$0 }
        END {
          last=0
          for (i=1;i<=NR;i++) if (a[i] ~ /^endmenu[[:space:]]*$/) last=i
          for (i=1;i<=NR;i++) {
            if (i==last) print "source \"security/baseband-guard/Kconfig\""
            print a[i]
          }
        }' security/Kconfig > security/Kconfig.tmp
      mv security/Kconfig.tmp security/Kconfig
    else
      printf '\nsource "security/baseband-guard/Kconfig"\n' >> security/Kconfig
    fi
  fi
fi

# Record integration metadata for artifacts/docs.
mkdir -p "${KERNEL_SRC}/.bbg-integration"
cat > "${KERNEL_SRC}/.bbg-integration/info.txt" <<EOF
bbg_repo=${BBG_REPO}
bbg_ref=${BBG_REF}
bbg_sha=${BBG_SHA}
integrated_at_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF

# Export SHA for callers
echo "${BBG_SHA}" > "${KERNEL_SRC}/.bbg-integration/bbg.sha"
echo "[+] Baseband-guard integrated"
