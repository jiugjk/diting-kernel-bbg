# Mapping: kpm-panda-hide -> STATIC zero-kprobe patches (preferred)
#
# Upstream KPM                         Static call site (CONFIG_PANDA_HIDE)
# -----------------------------------  ---------------------------------------------
# seq_put_decimal_ull TracerPid        fs/proc/array.c  task_state(): tpid = 0
# seq_puts "t (tracing stop)"          fs/proc/array.c  task_state(): force S (sleeping)
# do_task_stat state 't'               fs/proc/array.c  do_task_stat(): state = 'S'
# proc_pid_wchan ptrace_stop           fs/proc/base.c   proc_pid_wchan(): print '0'
# show_map_vma maps filter             fs/proc/task_mmu.c show_map(): rollback m->count
# __get_task_comm rename               fs/exec.c        __get_task_comm(): sanitize_comm
# openat/faccessat -ENOENT             fs/open.c        do_sys_openat2 / do_faccessat
# connect ports                        security/panda-hide/panda_lsm.c socket_connect
# access_remote_vm scrub               mm/memory.c      access_remote_vm(): scrub_mem
#
# Shared policy: security/panda-hide/panda_policy.c
# Public header: include/linux/panda_hide.h
# Apply tool:    scripts/apply-panda-static.py
#
# Optional: CONFIG_PANDA_HIDE_KPROBES builds the old runtime backend (default n).
