#!/usr/bin/env bash
# Fix incomplete Xiaomi OSS trees for kconfig + build.
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
  [[ -f "${rel}" ]] && return 0
  mkdir -p "$(dirname "${rel}")"
  cat > "${rel}" <<EOF
# SPDX-License-Identifier: GPL-2.0
# Auto-stub by fix-oss-kconfig.sh for missing OSS path: ${rel}
EOF
  echo "  [stub-kconfig] ${rel}"
  created=$((created + 1))
}

stub_makefile() {
  local rel="$1"
  [[ -f "${rel}" ]] && return 0
  mkdir -p "$(dirname "${rel}")"
  cat > "${rel}" <<'EOF'
# SPDX-License-Identifier: GPL-2.0
# Auto-stub — directory incomplete in Xiaomi OSS; produce no objects.
EOF
  echo "  [stub-makefile] ${rel}"
  created=$((created + 1))
}

# 1) Explicit known holes on diting OSS
for rel in \
  drivers/misc/hwid/Kconfig \
  drivers/misc/plaid/Kconfig \
  drivers/misc/mi_gamekey/Kconfig
do
  stub_kconfig "${rel}"
done
for rel in \
  drivers/misc/hwid/Makefile \
  drivers/misc/plaid/Makefile \
  drivers/misc/mi_gamekey/Makefile
do
  # only stub makefile if the dir would be entered by obj-y / missing makefile
  if [[ ! -f "${rel}" ]]; then
    stub_makefile "${rel}"
  fi
done

# 2) Generic: any `source "....Kconfig"` whose file is missing.
# Use grep (always present); do NOT depend on rg.
while IFS= read -r line; do
  # line example: source "drivers/misc/plaid/Kconfig"
  rel="${line#*\"}"
  rel="${rel%%\"*}"
  [[ "${rel}" == *Kconfig* ]] || continue
  [[ -f "${rel}" ]] && continue
  stub_kconfig "${rel}"
done < <(grep -R --include='Kconfig*' -h -E '^\s*source\s+"[^"]+Kconfig[^"]*"' \
  drivers arch fs net sound security 2>/dev/null || true)

# 3) Generic: drivers/misc obj-y += foo/ without Makefile
if [[ -f drivers/misc/Makefile ]]; then
  while IFS= read -r sub; do
    [[ -n "${sub}" ]] || continue
    if [[ ! -f "drivers/misc/${sub}/Makefile" ]]; then
      stub_makefile "drivers/misc/${sub}/Makefile"
    fi
    if [[ ! -f "drivers/misc/${sub}/Kconfig" ]]; then
      # parent may source it; ensure exists
      stub_kconfig "drivers/misc/${sub}/Kconfig"
    fi
  done < <(grep -E 'obj-(y|\$\(CONFIG_[A-Z0-9_]*\))' drivers/misc/Makefile \
    | grep -oE '[A-Za-z0-9_-]+/' | tr -d '/' | sort -u)
fi

echo "[+] OSS fixups created: ${created}"

# sanity: every source in drivers/misc/Kconfig must now resolve
if [[ -f drivers/misc/Kconfig ]]; then
  miss=0
  while IFS= read -r line; do
    rel="${line#*\"}"; rel="${rel%%\"*}"
    if [[ ! -f "${rel}" ]]; then
      echo "  [ERROR] still missing: ${rel}"
      miss=$((miss + 1))
    fi
  done < <(grep -E '^\s*source\s+"' drivers/misc/Kconfig || true)
  if [[ "${miss}" -gt 0 ]]; then
    echo "[ERROR] ${miss} Kconfig source(s) still missing" >&2
    exit 1
  fi
  echo "[+] drivers/misc/Kconfig sources all resolvable"
fi
