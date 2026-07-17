// SPDX-License-Identifier: GPL-2.0
/*
 * frida_hide — port of kpm-panda-hide/src/frida_hide.c
 *
 * Upstream:
 *   show_map_vma before/after: drop newly written maps lines containing
 *     frida|gadget|linjector|gmain
 *   __get_task_comm after: rewrite banned thread names to "binder"
 */
#include "panda_common.h"

#ifdef CONFIG_ARM64
#define PH_ARG0(regs) ((regs)->regs[0])
#define PH_ARG1(regs) ((regs)->regs[1])
#else
#define PH_ARG0(regs) 0UL
#define PH_ARG1(regs) 0UL
#endif

/* ---- show_map_vma ---- */
struct map_ctx {
	struct seq_file *m;
	size_t prev_count;
	bool valid;
};

static int is_hidden_map_region(struct seq_file *m, size_t prev_count)
{
	static const char * const block_str[] = {
		"frida",
		"gadget",
		"linjector",
		"gmain",
	};
	char *start;
	size_t new_len;
	char saved;
	int i, found = 0;

	if (!m || !m->buf || m->count < prev_count)
		return 0;
	start = m->buf + prev_count;
	new_len = m->count - prev_count;
	if (!new_len)
		return 0;

	/* Temporarily NUL-terminate the newly written slice (upstream O0 trick) */
	saved = start[new_len];
	start[new_len] = '\0';
	for (i = 0; i < ARRAY_SIZE(block_str); i++) {
		if (strstr(start, block_str[i])) {
			found = 1;
			break;
		}
	}
	start[new_len] = saved;
	return found;
}

static int entry_show_map_vma(struct kretprobe_instance *ri, struct pt_regs *regs)
{
	struct map_ctx *ctx = (struct map_ctx *)ri->data;
	struct seq_file *m = (struct seq_file *)PH_ARG0(regs);

	ctx->m = m;
	if (m && m->buf) {
		ctx->prev_count = m->count;
		ctx->valid = true;
	} else {
		ctx->valid = false;
	}
	return 0;
}

static int ret_show_map_vma(struct kretprobe_instance *ri, struct pt_regs *regs)
{
	struct map_ctx *ctx = (struct map_ctx *)ri->data;
	struct seq_file *m;

	if (!panda_hide_frida || !ctx->valid)
		return 0;
	m = ctx->m;
	if (!m || !m->buf)
		return 0;
	if (is_hidden_map_region(m, ctx->prev_count))
		m->count = ctx->prev_count;
	return 0;
}

static struct kretprobe krp_show_map_vma = {
	.kp.symbol_name = "show_map_vma",
	.handler = ret_show_map_vma,
	.entry_handler = entry_show_map_vma,
	.data_size = sizeof(struct map_ctx),
	.maxactive = 64,
};

/* ---- __get_task_comm(buf, buf_size, tsk) ---- */
struct comm_ctx {
	char *buf;
	size_t buf_len;
};

static int entry_get_task_comm(struct kretprobe_instance *ri, struct pt_regs *regs)
{
	struct comm_ctx *ctx = (struct comm_ctx *)ri->data;

	ctx->buf = (char *)PH_ARG0(regs);
	ctx->buf_len = (size_t)PH_ARG1(regs);
	return 0;
}

static int ret_get_task_comm(struct kretprobe_instance *ri, struct pt_regs *regs)
{
	struct comm_ctx *ctx = (struct comm_ctx *)ri->data;
	static const char fake[] = "binder";
	size_t fake_len = sizeof(fake) - 1;
	size_t len;

	if (!panda_hide_frida || !ctx->buf || !ctx->buf_len)
		return 0;
	if (!panda_is_hidden_comm(ctx->buf))
		return 0;

	len = strnlen(ctx->buf, ctx->buf_len);
	if (len >= fake_len) {
		memcpy(ctx->buf, fake, fake_len);
		ctx->buf[fake_len] = '\0';
	} else if (len) {
		memcpy(ctx->buf, fake, len);
		ctx->buf[len] = '\0';
	}
	return 0;
}

static struct kretprobe krp_get_task_comm = {
	.kp.symbol_name = "__get_task_comm",
	.handler = ret_get_task_comm,
	.entry_handler = entry_get_task_comm,
	.data_size = sizeof(struct comm_ctx),
	.maxactive = 64,
};

static bool reg_map;
static bool reg_comm;

int panda_frida_init(void)
{
	int err;

	err = register_kretprobe(&krp_show_map_vma);
	if (err)
		pr_warn(PH_TAG "kretprobe show_map_vma failed: %d\n", err);
	else
		reg_map = true;

	err = register_kretprobe(&krp_get_task_comm);
	if (err)
		pr_warn(PH_TAG "kretprobe __get_task_comm failed: %d\n", err);
	else
		reg_comm = true;

	pr_info(PH_TAG "frida hide installed\n");
	return 0;
}

void panda_frida_exit(void)
{
	if (reg_comm)
		unregister_kretprobe(&krp_get_task_comm);
	if (reg_map)
		unregister_kretprobe(&krp_show_map_vma);
	pr_info(PH_TAG "frida hide uninstalled\n");
}
