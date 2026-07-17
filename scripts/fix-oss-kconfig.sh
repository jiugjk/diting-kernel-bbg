#!/usr/bin/env bash
# Fix incomplete Xiaomi OSS trees:
#  1) stub missing Kconfig files referenced by source "..."
#  2) stub missing subdir Makefile for obj-y += hwid/ style holes
# Usage: fix-oss-kconfig.sh <kernel_src>
set -euo pipefail

KERNEL_SRC="${1:-}"
[[ -n "${KERNEL_SRC}" && -d "${KERNEL_SRC}" ]] || {
  echo "Usage: $0 <kernel_src>" >&2
  exit 2
}
KERNEL_SRC="$(cd "${KERNEL_SRC}" && pwd)"
cd "${KERNEL_SRC}"

echo "[+] Fixing incomplete Xiaomi OSS under ${KERNEL_SRC}"
created=0

stub_kconfig() {
  local rel="$1"
  local note="${2:-Missing from Xiaomi OSS export}"
  if [[ -f "${rel}" ]]; then
    return 0
  fi
  mkdir -p "$(dirname "${rel}")"
  cat > "${rel}" <<EOF
# SPDX-License-Identifier: GPL-2.0
# Auto-stub by fix-oss-kconfig.sh — ${note}
# Empty on purpose so parent Kconfig can source this path.
EOF
  echo "  [stub-kconfig] ${rel}"
  created=$((created+1))
}

stub_makefile() {
  local rel="$1"
  if [[ -f "${rel}" ]]; then
    return 0
  fi
  mkdir -p "$(dirname "${rel}")"
  cat > "${rel}" <<'EOF'
# SPDX-License-Identifier: GPL-2.0
# Auto-stub by fix-oss-kconfig.sh — directory not published in OSS.
# Produce no objects.
EOF
  echo "  [stub-makefile] ${rel}"
  created=$((created+1))
}

# --- Known Xiaomi diting OSS holes ---
if [[ ! -d drivers/misc/hwid ]] || [[ ! -f drivers/misc/hwid/Kconfig ]]; then
  stub_kconfig "drivers/misc/hwid/Kconfig" "drivers/misc/hwid unpublished"
  stub_makefile "drivers/misc/hwid/Makefile"
fi

# Generic: missing sourced Kconfig files
if command -v rg >/dev/null 2>&1; then
  while IFS= read -r rel; do
    [[ -n "${rel}" ]] || continue
    [[ -f "${rel}" ]] && continue
    stub_kconfig "${rel}" "referenced by source but missing"
  done < <(rg -N --no-filename -o 'source\s+"[^"]+Kconfig[^"]*"' \
    drivers arch fs net sound security 2>/dev/null \
    | sed 's/.*"\([^"]*\)"/\1/' | sort -u || true)
fi

# Generic: parent Makefile has obj-y += foo/ but foo/Makefile missing
# (only for drivers/misc for safety — avoid broad tree mutation)
if [[ -f drivers/misc/Makefile ]]; then
  while IFS= read -r sub; do
    [[ -n "${sub}" ]] || continue
    if [[ ! -f "drivers/misc/${sub}/Makefile" ]]; then
      stub_makefile "drivers/misc/${sub}/Makefile"
      # if no Kconfig and parent sources it, already handled; else ensure empty dir ok
    fi
  done < <(sed -n 's/.*obj-\$(CONFIG_[A-Z0-9_]*).*+=[[:space:]]*\([a-zA-Z0-9_-]*\)\/.*/\1/p; s/.*obj-y[[:space:]]*+=[[:space:]]*\([a-zA-Z0-9_-]*\)\/.*/\1/p' drivers/misc/Makefile | sort -u)
fi

echo "[+] OSS fixups created: ${created}"
