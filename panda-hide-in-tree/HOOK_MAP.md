# Mapping: kpm-panda-hide -> in-tree panda-hide
#
# Source (KPM)              Symbol / API                      In-tree file          Mechanism
# ------------------------- --------------------------------- --------------------- --------------------
# debugger_hide.c           seq_put_decimal_ull + hook_wrap3  panda_debugger.c      kprobe pre
# debugger_hide.c           seq_puts + hook_wrap2             panda_debugger.c      kprobe pre
# debugger_hide.c           proc_pid_wchan + hook_wrap4 after panda_debugger.c      kretprobe
# debugger_hide.c           do_task_stat + hook_wrap5 after   panda_debugger.c      kretprobe
# frida_hide.c              show_map_vma before/after         panda_frida.c         kretprobe
# frida_hide.c              __get_task_comm after             panda_frida.c         kretprobe
# openat_hide.c             fp_hook_syscalln(__NR_openat)     panda_lsm.c           LSM file_open
# openat_hide.c             fp_hook_syscalln(__NR_faccessat)  panda_lsm.c           LSM file_open (path)
# net_hide.c                fp_hook_syscalln(__NR_connect)    panda_lsm.c           LSM socket_connect
# mem_hide.c                access_remote_vm after            panda_mem.c           kretprobe
# main.c                    KPM_INIT/EXIT                     panda_main.c          device_initcall
#
# Intentional differences:
# 1. No KernelPatch dependency (kpmodule/hook/fp_hook_syscalln removed).
# 2. faccessat coverage is weaker without full path in inode_permission; file_open
#    covers the common openat detection path used by packs.
# 3. Hot-path kprobes on seq_puts/seq_put_decimal_ull have global effect; same as upstream KPM.
# 4. Requires CONFIG_KPROBES + CONFIG_KALLSYMS + CONFIG_SECURITY.
