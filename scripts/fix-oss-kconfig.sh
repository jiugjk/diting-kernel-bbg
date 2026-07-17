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

stub_makefile_empty() {
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

install_hwid_stub() {
  # Xiaomi did not publish drivers/misc/hwid on bsp-diting-s-oss, but:
  #  - drivers/misc/Makefile: obj-y += hwid/ and -I.../hwid
  #  - drivers/soc/qcom/icnss2/qmi.c includes hwid.h and calls:
  #      get_hw_country_version(), get_hw_version_platform()
  #      HARDWARE_PROJECT_L9S, CountryGlobal
  mkdir -p drivers/misc/hwid
  if [[ ! -f drivers/misc/hwid/hwid.h ]]; then
    cat > drivers/misc/hwid/hwid.h <<'EOF'
/* SPDX-License-Identifier: GPL-2.0 */
/*
 * Minimal OSS stub for unpublished Xiaomi hwid driver.
 * Enough for icnss2 BDF filename selection to compile and take the
 * generic path (non-L9S).
 */
#ifndef __XIAOMI_HWID_STUB_H__
#define __XIAOMI_HWID_STUB_H__

#include <linux/types.h>

/* Country codes used by vendor WLAN BDF selection */
enum {
	CountryCN = 0,
	CountryGlobal = 1,
	CountryIndia = 2,
};

/* Project IDs — only L9S is referenced by diting icnss2 code */
#ifndef HARDWARE_PROJECT_UNKNOWN
#define HARDWARE_PROJECT_UNKNOWN	0
#endif
#ifndef HARDWARE_PROJECT_L9S
#define HARDWARE_PROJECT_L9S		0x4C3953 /* 'L9S' tag, not matched by stub */
#endif

uint32_t get_hw_country_version(void);
uint32_t get_hw_version_platform(void);
uint32_t get_hw_version_major(void);
uint32_t get_hw_version_minor(void);
uint32_t get_hwid_value(void);

#endif /* __XIAOMI_HWID_STUB_H__ */
EOF
    echo "  [stub-header] drivers/misc/hwid/hwid.h"
    created=$((created + 1))
  fi

  if [[ ! -f drivers/misc/hwid/hwid.c ]]; then
    cat > drivers/misc/hwid/hwid.c <<'EOF'
// SPDX-License-Identifier: GPL-2.0
/*
 * Minimal OSS stub implementation of Xiaomi hwid helpers.
 * Returns Global + unknown project so WLAN uses default BDF names.
 */
#include <linux/module.h>
#include <linux/kernel.h>
#include "hwid.h"

uint32_t get_hw_country_version(void)
{
	return (uint32_t)CountryGlobal;
}
EXPORT_SYMBOL_GPL(get_hw_country_version);

uint32_t get_hw_version_platform(void)
{
	/* Not HARDWARE_PROJECT_L9S → default bdwlan.elf path in icnss2 */
	return HARDWARE_PROJECT_UNKNOWN;
}
EXPORT_SYMBOL_GPL(get_hw_version_platform);

uint32_t get_hw_version_major(void)
{
	return 0;
}
EXPORT_SYMBOL_GPL(get_hw_version_major);

uint32_t get_hw_version_minor(void)
{
	return 0;
}
EXPORT_SYMBOL_GPL(get_hw_version_minor);

uint32_t get_hwid_value(void)
{
	return 0;
}
EXPORT_SYMBOL_GPL(get_hwid_value);

MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Xiaomi hwid OSS stub");
EOF
    echo "  [stub-source] drivers/misc/hwid/hwid.c"
    created=$((created + 1))
  fi

  # Always (re)write Makefile so we actually build the stub objects.
  # Empty stub Makefile from earlier runs would leave unresolved symbols.
  cat > drivers/misc/hwid/Makefile <<'EOF'
# SPDX-License-Identifier: GPL-2.0
# OSS stub hwid driver (upstream sources not published for this branch)
obj-y += hwid.o
EOF
  echo "  [stub-makefile] drivers/misc/hwid/Makefile (with hwid.o)"
  created=$((created + 1))

  stub_kconfig "drivers/misc/hwid/Kconfig"
}

# 1) hwid is special: needs real header + symbols, not empty Makefile
install_hwid_stub

# 2) other known empty holes
for rel in \
  drivers/misc/plaid/Kconfig \
  drivers/misc/mi_gamekey/Kconfig
do
  stub_kconfig "${rel}"
done
for rel in \
  drivers/misc/plaid/Makefile \
  drivers/misc/mi_gamekey/Makefile
do
  if [[ ! -f "${rel}" ]]; then
    stub_makefile_empty "${rel}"
  fi
done

# 3) Generic: any `source "....Kconfig"` whose file is missing.
while IFS= read -r line; do
  rel="${line#*\"}"
  rel="${rel%%\"*}"
  [[ "${rel}" == *Kconfig* ]] || continue
  [[ -f "${rel}" ]] && continue
  stub_kconfig "${rel}"
done < <(grep -R --include='Kconfig*' -h -E '^\s*source\s+"[^"]+Kconfig[^"]*"' \
  drivers arch fs net sound security 2>/dev/null || true)

# 4) Generic: drivers/misc obj-y += foo/ without Makefile (except hwid handled above)
if [[ -f drivers/misc/Makefile ]]; then
  while IFS= read -r sub; do
    [[ -n "${sub}" ]] || continue
    [[ "${sub}" == "hwid" ]] && continue
    if [[ ! -f "drivers/misc/${sub}/Makefile" ]]; then
      stub_makefile_empty "drivers/misc/${sub}/Makefile"
    fi
    if [[ ! -f "drivers/misc/${sub}/Kconfig" ]]; then
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

# sanity: hwid symbols present
if [[ ! -f drivers/misc/hwid/hwid.h || ! -f drivers/misc/hwid/hwid.c ]]; then
  echo "[ERROR] hwid stub incomplete" >&2
  exit 1
fi
echo "[+] hwid stub ready (hwid.h + hwid.c)"
