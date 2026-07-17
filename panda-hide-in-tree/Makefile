# SPDX-License-Identifier: GPL-2.0
obj-$(CONFIG_PANDA_HIDE) += panda_hide.o

# Always: policy helpers + LSM (socket_connect / optional file_open)
panda_hide-y := panda_policy.o panda_lsm.o

# Optional runtime kprobe backend (default off when static patches used)
panda_hide-$(CONFIG_PANDA_HIDE_KPROBES) += \
	panda_common.o \
	panda_debugger.o \
	panda_frida.o \
	panda_path.o \
	panda_mem.o \
	panda_main.o
