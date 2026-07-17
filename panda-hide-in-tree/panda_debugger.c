// SPDX-License-Identifier: GPL-2.0
/*
 * debugger_hide — port of kpm-panda-hide/src/debugger_hide.c
 *
 * Upstream:
 *   before seq_put_decimal_ull: if label "\nTracerPid:\t" force value 0
 *   before seq_puts: replace "t (tracing stop)" with "S (sleeping)"
 *   after  proc_pid_wchan: if buf=="ptrace_stop" rewrite to "0"
 *   after  do_task_stat: state char after ") "  't' -> 'S'
 */
#include "panda_common.h"

#ifdef CONFIG_ARM64
#define PH_ARG0(regs) ((regs)->regs[0])
#define PH_ARG1(regs) ((regs)->regs[1])
#define PH_ARG2(regs) ((regs)->regs[2])
#else
/* Fallback for non-arm64 build hosts; diting is arm64-only at runtime */
#define PH_ARG0(regs) 0UL
#define PH_ARG1(regs) 0UL
#define PH_ARG2(regs) 0UL
#endif

/* ---- seq_put_decimal_ull(m, delimiter, num) ---- */
static int pre_seq_put_decimal_ull(struct kprobe *p, struct pt_regs *regs)
{
	const char *delim;

	if (!panda_hide_debugger)
		return 0;

	delim = (const char *)PH_ARG1(regs);
	if (!delim)
		return 0;

	if (strcmp(delim, "\nTracerPid:\t") == 0 && PH_ARG2(regs) != 0)
		PH_ARG2(regs) = 0;
	return 0;
}

static struct kprobe kp_seq_put_decimal_ull = {
	.symbol_name = "seq_put_decimal_ull",
	.pre_handler = pre_seq_put_decimal_ull,
};

/* ---- seq_puts(m, s) ---- */
static const char sleeping_str[] = "S (sleeping)";

static int pre_seq_puts(struct kprobe *p, struct pt_regs *regs)
{
	const char *s;

	if (!panda_hide_debugger)
		return 0;

	s = (const char *)PH_ARG1(regs);
	if (!s)
		return 0;
	if (strcmp(s, "t (tracing stop)") == 0)
		PH_ARG1(regs) = (unsigned long)sleeping_str;
	return 0;
}

static struct kprobe kp_seq_puts = {
	.symbol_name = "seq_puts",
	.pre_handler = pre_seq_puts,
};

/* ---- proc_pid_wchan after ---- */
struct wchan_ctx {
	struct seq_file *m;
};

static int entry_proc_pid_wchan(struct kretprobe_instance *ri, struct pt_regs *regs)
{
	struct wchan_ctx *ctx = (struct wchan_ctx *)ri->data;

	ctx->m = (struct seq_file *)PH_ARG0(regs);
	return 0;
}

static int ret_proc_pid_wchan(struct kretprobe_instance *ri, struct pt_regs *regs)
{
	struct wchan_ctx *ctx = (struct wchan_ctx *)ri->data;
	struct seq_file *m;

	if (!panda_hide_debugger)
		return 0;
	m = ctx->m;
	if (!m || !m->buf || !m->count)
		return 0;
	if (m->count >= 11 && strncmp(m->buf, "ptrace_stop", 11) == 0) {
		m->buf[0] = '0';
		m->buf[1] = '\0';
		m->count = 1;
	}
	return 0;
}

static struct kretprobe krp_proc_pid_wchan = {
	.kp.symbol_name = "proc_pid_wchan",
	.handler = ret_proc_pid_wchan,
	.entry_handler = entry_proc_pid_wchan,
	.data_size = sizeof(struct wchan_ctx),
	.maxactive = 32,
};

/* ---- do_task_stat after ---- */
struct stat_ctx {
	struct seq_file *m;
};

static int entry_do_task_stat(struct kretprobe_instance *ri, struct pt_regs *regs)
{
	struct stat_ctx *ctx = (struct stat_ctx *)ri->data;

	ctx->m = (struct seq_file *)PH_ARG0(regs);
	return 0;
}

static int ret_do_task_stat(struct kretprobe_instance *ri, struct pt_regs *regs)
{
	struct stat_ctx *ctx = (struct stat_ctx *)ri->data;
	struct seq_file *m;
	size_t i;

	if (!panda_hide_debugger)
		return 0;
	m = ctx->m;
	if (!m || !m->buf || m->count < 3)
		return 0;

	for (i = 0; i + 2 < m->count; i++) {
		if (m->buf[i] == ')' && m->buf[i + 1] == ' ') {
			if (m->buf[i + 2] == 't')
				m->buf[i + 2] = 'S';
			break;
		}
	}
	return 0;
}

static struct kretprobe krp_do_task_stat = {
	.kp.symbol_name = "do_task_stat",
	.handler = ret_do_task_stat,
	.entry_handler = entry_do_task_stat,
	.data_size = sizeof(struct stat_ctx),
	.maxactive = 32,
};

static bool reg_seq_put;
static bool reg_seq_puts;
static bool reg_wchan;
static bool reg_stat;

int panda_debugger_init(void)
{
	int err;

	err = register_kprobe(&kp_seq_put_decimal_ull);
	if (err) {
		pr_warn(PH_TAG "kprobe seq_put_decimal_ull failed: %d\n", err);
	} else {
		reg_seq_put = true;
	}

	err = register_kprobe(&kp_seq_puts);
	if (err) {
		pr_warn(PH_TAG "kprobe seq_puts failed: %d\n", err);
	} else {
		reg_seq_puts = true;
	}

	err = register_kretprobe(&krp_proc_pid_wchan);
	if (err) {
		pr_warn(PH_TAG "kretprobe proc_pid_wchan failed: %d\n", err);
	} else {
		reg_wchan = true;
	}

	err = register_kretprobe(&krp_do_task_stat);
	if (err) {
		pr_warn(PH_TAG "kretprobe do_task_stat failed: %d\n", err);
	} else {
		reg_stat = true;
	}

	pr_info(PH_TAG "debugger hide installed (kprobe/kretprobe)\n");
	return 0;
}

void panda_debugger_exit(void)
{
	if (reg_stat)
		unregister_kretprobe(&krp_do_task_stat);
	if (reg_wchan)
		unregister_kretprobe(&krp_proc_pid_wchan);
	if (reg_seq_puts)
		unregister_kprobe(&kp_seq_puts);
	if (reg_seq_put)
		unregister_kprobe(&kp_seq_put_decimal_ull);
	pr_info(PH_TAG "debugger hide uninstalled\n");
}
