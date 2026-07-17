// SPDX-License-Identifier: GPL-2.0
/*
 * Path hide via kprobes — port of openat_hide.c
 *
 * Upstream: fp_hook_syscalln(openat/faccessat) + skip_origin + ret=-ENOENT
 * In-tree: kprobe pre_handler returns 1 (skip probed insn) after emulating
 *          an immediate function return of -ENOENT on arm64 (PC <- LR, X0=-ENOENT).
 *
 * Complements LSM file_open in panda_lsm.c.
 */
#include "panda_common.h"

#ifdef CONFIG_ARM64
#include <asm/ptrace.h>

#define PH_ARG1(regs) ((regs)->regs[1])

static void ph_emulate_return_enoent(struct pt_regs *regs)
{
	regs->regs[0] = (unsigned long)(-ENOENT);
	/*
	 * Jump to the caller's return address (x30), skipping the rest of the
	 * probed function. Combined with pre_handler returning non-zero, this
	 * approximates KernelPatch skip_origin + ret.
	 */
	instruction_pointer_set(regs, procedure_link_pointer(regs));
}
#else
#define PH_ARG1(regs) 0UL
static void ph_emulate_return_enoent(struct pt_regs *regs) { }
#endif

static int try_block_user_path(struct pt_regs *regs, const char *tag)
{
	const char __user *filename;
	char buf[256];
	long n;

	if (!panda_hide_path)
		return 0;

	filename = (const char __user *)PH_ARG1(regs);
	if (!filename)
		return 0;

	n = strncpy_from_user(buf, filename, sizeof(buf));
	if (n <= 0 || n >= (long)sizeof(buf))
		return 0;

	if (!panda_is_hidden_path(buf))
		return 0;

	pr_info(PH_TAG "%s BLOCKED: %s\n", tag, buf);
	ph_emulate_return_enoent(regs);
	return 1; /* ask kprobes to skip single-step of original insn */
}

static int pre_do_sys_openat2(struct kprobe *p, struct pt_regs *regs)
{
	return try_block_user_path(regs, "openat");
}

static int pre_do_faccessat(struct kprobe *p, struct pt_regs *regs)
{
	return try_block_user_path(regs, "faccessat");
}

static struct kprobe kp_openat2 = {
	.symbol_name = "do_sys_openat2",
	.pre_handler = pre_do_sys_openat2,
};

static struct kprobe kp_faccessat = {
	.symbol_name = "do_faccessat",
	.pre_handler = pre_do_faccessat,
};

static bool reg_open;
static bool reg_acc;
static bool used_open_alt;

/* Some trees still expose do_sys_open(dfd, filename, flags, mode) */
static struct kprobe kp_open_legacy = {
	.symbol_name = "do_sys_open",
	.pre_handler = pre_do_sys_openat2,
};

int panda_path_kprobe_init(void)
{
	int err;

	err = register_kprobe(&kp_openat2);
	if (err) {
		pr_warn(PH_TAG "kprobe do_sys_openat2 failed: %d, trying do_sys_open\n", err);
		err = register_kprobe(&kp_open_legacy);
		if (err)
			pr_warn(PH_TAG "kprobe do_sys_open failed: %d (LSM open remains)\n", err);
		else {
			reg_open = true;
			used_open_alt = true;
		}
	} else {
		reg_open = true;
	}

	err = register_kprobe(&kp_faccessat);
	if (err)
		pr_warn(PH_TAG "kprobe do_faccessat failed: %d\n", err);
	else
		reg_acc = true;

	pr_info(PH_TAG "path kprobes open=%d faccess=%d\n", reg_open, reg_acc);
	return 0;
}

void panda_path_kprobe_exit(void)
{
	if (reg_acc)
		unregister_kprobe(&kp_faccessat);
	if (reg_open) {
		if (used_open_alt)
			unregister_kprobe(&kp_open_legacy);
		else
			unregister_kprobe(&kp_openat2);
	}
}
