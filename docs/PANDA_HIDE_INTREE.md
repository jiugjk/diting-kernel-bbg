# panda-hide in-tree port — design notes

## Goal

Fuse [kpm-panda-hide](https://github.com/P4nda0s/kpm-panda-hide) **logic** into the
Android 12 / Linux 5.10 kernel **without KernelPatch runtime**, so it boots as
part of the kernel image (`CONFIG_PANDA_HIDE=y`).

## Why not drop KPM sources as-is?

Upstream is a **KernelPatch KPM**:

- `#include <kpmodule.h> / <hook.h> / <syscall.h>`
- `hook_wrapN()` / `fp_hook_syscalln()` / `unhook()`
- Builds with `aarch64-none-elf-gcc -r` into `panda-hide.kpm`

Those symbols only exist inside KernelPatch. Linking the KPM `.c` files into
`vmlinux` will not compile.

## Symbol / behavior map

See `panda-hide-in-tree/HOOK_MAP.md` for the full table.

| Feature | Upstream | In-tree |
|---------|----------|---------|
| TracerPid=0 | hook `seq_put_decimal_ull` | kprobe pre |
| tracing stop text | hook `seq_puts` | kprobe pre |
| wchan ptrace_stop | after `proc_pid_wchan` | kretprobe |
| stat state `t`→`S` | after `do_task_stat` | kretprobe |
| maps frida lines | before/after `show_map_vma` | kretprobe |
| thread names | after `__get_task_comm` | kretprobe |
| openat/faccessat | `fp_hook_syscalln` | kprobe + LSM `file_open` |
| connect ports | `fp_hook_syscalln` | LSM `socket_connect` |
| mem scrub | after `access_remote_vm` | kretprobe |

## Integration path

```
scripts/integrate-panda-hide.sh  →  security/panda-hide/*
security/Makefile                += obj-$(CONFIG_PANDA_HIDE) += panda-hide/
security/Kconfig                 += source "security/panda-hide/Kconfig"
config/panda-hide.fragment       →  merged at build time
CONFIG_LSM                       += ,panda_hide
```

## Residual differences vs KPM

1. **No runtime load/unload** as `.kpm` (built-in; params under sysfs if modular build ever used).
2. **faccessat/openat** emulate `-ENOENT` via arm64 PC←LR kprobe technique; if a symbol is renamed, soft-fails to LSM-only open path.
3. **Hot-path kprobes** on `seq_puts` / `seq_put_decimal_ull` match upstream global scope — keep that in mind for performance.
4. Requires `CONFIG_KPROBES=y` and `CONFIG_KALLSYMS=y`.

## Verification ideas (on device; not done by CI)

```bash
dmesg | grep panda-hide
cat /proc/self/status | grep TracerPid   # while ptraced — expect 0
# open frida-agent path — expect ENOENT
# connect to 27042 from non-adbd — expect ECONNREFUSED
```
