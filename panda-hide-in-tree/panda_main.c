// SPDX-License-Identifier: GPL-2.0
/*
 * panda-hide main — in-tree port of kpm-panda-hide
 * Original: https://github.com/P4nda0s/kpm-panda-hide (KPM / KernelPatch)
 */
#include "panda_common.h"

int panda_path_kprobe_init(void);
void panda_path_kprobe_exit(void);

static int __init panda_hide_init(void)
{
	pr_info(PH_TAG "init (in-tree port of kpm-panda-hide v2.0.0)\n");

	/* Order mirrors upstream main.c install order */
	panda_debugger_init();
	panda_frida_init();
	panda_path_kprobe_init();
	/* net: LSM socket_connect in panda_lsm.c */
	panda_mem_init();

	pr_info(PH_TAG "all features scheduled (kprobes + LSM)\n");
	return 0;
}

static void __exit panda_hide_exit(void)
{
	panda_mem_exit();
	panda_path_kprobe_exit();
	panda_frida_exit();
	panda_debugger_exit();
	pr_info(PH_TAG "exit\n");
}

/*
 * Kprobes need a relatively late init (kprobes subsystem ready).
 * LSM registers earlier via DEFINE_LSM in panda_lsm.c.
 */
device_initcall(panda_hide_init);

#ifdef MODULE
module_exit(panda_hide_exit);
#endif

MODULE_LICENSE("GPL");
MODULE_AUTHOR("pandaos (original KPM); in-tree port for diting");
MODULE_DESCRIPTION("panda-hide: frida & debugger hiding (in-tree port)");
MODULE_VERSION("2.0.0-intree");
