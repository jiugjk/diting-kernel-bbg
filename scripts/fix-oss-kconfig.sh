#!/usr/bin/env bash
# Fix incomplete / broken Xiaomi OSS sources for diting build.
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
  mkdir -p drivers/misc/hwid
  # Always refresh header/source so symbol list stays complete across iterations.
  cat > drivers/misc/hwid/hwid.h <<'EOF'
/* SPDX-License-Identifier: GPL-2.0 */
/*
 * Minimal OSS stub for unpublished Xiaomi hwid driver.
 * Symbols required by icnss2/cnss2 BDF selection on bsp-diting-s-oss.
 */
#ifndef __XIAOMI_HWID_STUB_H__
#define __XIAOMI_HWID_STUB_H__

#include <linux/types.h>

/* Country codes used by vendor WLAN BDF selection */
enum {
	CountryCN = 0,
	CountryGlobal = 1,
	CountryIndia = 2,
	CountryJapan = 3,
};

/* Project IDs referenced by cnss2/icnss2 qmi.c */
#define HARDWARE_PROJECT_UNKNOWN	0
#define HARDWARE_PROJECT_L1		1
#define HARDWARE_PROJECT_L1A		2
#define HARDWARE_PROJECT_L2		3
#define HARDWARE_PROJECT_L2S		4
#define HARDWARE_PROJECT_L3		5
#define HARDWARE_PROJECT_L3S		6
#define HARDWARE_PROJECT_L9S		7
#define HARDWARE_PROJECT_L10		8
#define HARDWARE_PROJECT_L12		9
#define HARDWARE_PROJECT_L18		10

uint32_t get_hw_country_version(void);
uint32_t get_hw_version_platform(void);
uint32_t get_hw_version_major(void);
uint32_t get_hw_version_minor(void);
uint32_t get_hwid_value(void);

#endif /* __XIAOMI_HWID_STUB_H__ */
EOF
  echo "  [stub-header] drivers/misc/hwid/hwid.h"
  created=$((created + 1))

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
	/* Not matching L1/L2/.../L9S → default bdwlan path in qmi.c */
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

  cat > drivers/misc/hwid/Makefile <<'EOF'
# SPDX-License-Identifier: GPL-2.0
# OSS stub hwid driver (upstream sources not published for this branch)
obj-y += hwid.o
EOF
  echo "  [stub-makefile] drivers/misc/hwid/Makefile (with hwid.o)"
  created=$((created + 1))

  stub_kconfig "drivers/misc/hwid/Kconfig"
}

fix_usb_gadget_async_dup() {
  # Xiaomi OSS udc/core.c contains two identical pairs of
  # usb_gadget_{enable,disable}_async_callbacks — compile fails with redefinition.
  local f="drivers/usb/gadget/udc/core.c"
  [[ -f "${f}" ]] || return 0
  if grep -c "usb_gadget_enable_async_callbacks" "${f}" | grep -q '^1$'; then
    echo "  [skip] ${f} async callbacks already unique"
    return 0
  fi
  python3 - <<'PY'
from pathlib import Path
p = Path("drivers/usb/gadget/udc/core.c")
text = p.read_text(errors="replace")
# Remove the first short undoc'd pair (before the kernel-doc block).
# Anchor on the undoc'd pair that uses spaces indentation.
old = """static inline void usb_gadget_enable_async_callbacks(struct usb_udc *udc)
{
        struct usb_gadget *gadget = udc->gadget;

        if (gadget->ops->udc_async_callbacks)
                gadget->ops->udc_async_callbacks(gadget, true);
}

static inline void usb_gadget_disable_async_callbacks(struct usb_udc *udc)
{
        struct usb_gadget *gadget = udc->gadget;

        if (gadget->ops->udc_async_callbacks)
                gadget->ops->udc_async_callbacks(gadget, false);
}

/**
 * usb_gadget_enable_async_callbacks - tell usb device controller to enable asynchronous callbacks
"""
new = """/**
 * usb_gadget_enable_async_callbacks - tell usb device controller to enable asynchronous callbacks
"""
if old not in text:
    # try tabs variant for the first pair
    old2 = old.replace("        ", "\t")
    if old2 in text:
        text = text.replace(old2, new, 1)
        p.write_text(text)
        print("  [fix] udc/core.c removed duplicate async callbacks (tabs)")
    else:
        # fallback: delete first occurrence of each function body only if count==2
        count = text.count("static inline void usb_gadget_enable_async_callbacks")
        print(f"  [warn] udc/core.c async callback count={count}, no exact anchor")
else:
    p.write_text(text.replace(old, new, 1))
    print("  [fix] udc/core.c removed duplicate async callbacks")
PY
  created=$((created + 1))
}


install_missing_vendor_hooks() {
  # Scan for #include <trace/hooks/foo.h> and create empty vendor-hook
  # headers when Xiaomi OSS omitted them (e.g. thermal.h).
  mkdir -p include/trace/hooks
  local includes
  includes=$(grep -Rho --include='*.c' --include='*.h' \
    '#include[[:space:]]*<trace/hooks/[a-zA-Z0-9_]*\.h>' . 2>/dev/null \
    | sed -E 's/.*<trace\/hooks\/([a-zA-Z0-9_]+)\.h>.*/\1/' | sort -u || true)

  # Always ensure known missing ones
  includes=$(printf '%s\n%s\n' "$includes" "thermal" | sort -u)

  local name hdr guard
  for name in $includes; do
    hdr="include/trace/hooks/${name}.h"
    [[ -f "${hdr}" ]] && continue
    guard="_TRACE_HOOK_$(echo "$name" | tr 'a-z' 'A-Z')_H"
    # Minimal no-op vendor hook header matching Android DECLARE_HOOK style.
    # Provide thermal hook used by thermal_core.c; others empty but valid.
    if [[ "${name}" == "thermal" ]]; then
      cat > "${hdr}" <<'EOF'
/* SPDX-License-Identifier: GPL-2.0 */
#undef TRACE_SYSTEM
#define TRACE_SYSTEM thermal
#define TRACE_INCLUDE_PATH trace/hooks
#if !defined(_TRACE_HOOK_THERMAL_H) || defined(TRACE_HEADER_MULTI_READ)
#define _TRACE_HOOK_THERMAL_H
#include <linux/tracepoint.h>
#include <trace/hooks/vendor_hooks.h>
/*
 * OSS stub: upstream Xiaomi tree references this header but did not publish it.
 * Provide the hook used by drivers/thermal/thermal_core.c as a no-op site.
 */
struct thermal_zone_device;
DECLARE_HOOK(android_vh_thermal_pm_notify_suspend,
	TP_PROTO(struct thermal_zone_device *tz, int *irq_wakeable),
	TP_ARGS(tz, irq_wakeable));
#endif /* _TRACE_HOOK_THERMAL_H */
/* This part must be outside protection */
#include <trace/define_trace.h>
EOF
    else
      cat > "${hdr}" <<EOF
/* SPDX-License-Identifier: GPL-2.0 */
/* Auto-stub missing vendor hook header: ${name}.h */
#undef TRACE_SYSTEM
#define TRACE_SYSTEM ${name}
#define TRACE_INCLUDE_PATH trace/hooks
#if !defined(${guard}) || defined(TRACE_HEADER_MULTI_READ)
#define ${guard}
#include <linux/tracepoint.h>
#include <trace/hooks/vendor_hooks.h>
#endif /* ${guard} */
#include <trace/define_trace.h>
EOF
    fi
    echo "  [stub-vhook] ${hdr}"
    created=$((created + 1))
  done
}


# --- run fixups ---
install_hwid_stub
fix_usb_gadget_async_dup

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

while IFS= read -r line; do
  rel="${line#*\"}"
  rel="${rel%%\"*}"
  [[ "${rel}" == *Kconfig* ]] || continue
  [[ -f "${rel}" ]] && continue
  stub_kconfig "${rel}"
done < <(grep -R --include='Kconfig*' -h -E '^\s*source\s+"[^"]+Kconfig[^"]*"' \
  drivers arch fs net sound security 2>/dev/null || true)

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

install_missing_vendor_hooks

echo "[+] hwid stub ready; usb gadget dup fix applied if needed"
