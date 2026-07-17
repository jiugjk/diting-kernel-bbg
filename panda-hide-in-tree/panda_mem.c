// SPDX-License-Identifier: GPL-2.0
/*
 * mem_hide — port of kpm-panda-hide/src/mem_hide.c
 *
 * Upstream after_access_remote_vm: on non-FOLL_WRITE, scrub frida sigs in buf.
 * access_remote_vm(mm, addr, buf, len, gup_flags)
 */
#include "panda_common.h"
#include <linux/mm.h>

#ifdef CONFIG_ARM64
#define PH_ARG0(regs) ((regs)->regs[0])
#define PH_ARG1(regs) ((regs)->regs[1])
#define PH_ARG2(regs) ((regs)->regs[2])
#define PH_ARG3(regs) ((regs)->regs[3])
#define PH_ARG4(regs) ((regs)->regs[4])
#else
#define PH_ARG0(regs) 0UL
#define PH_ARG1(regs) 0UL
#define PH_ARG2(regs) 0UL
#define PH_ARG3(regs) 0UL
#define PH_ARG4(regs) 0UL
#endif

#ifndef FOLL_WRITE
#define FOLL_WRITE 0x01
#endif

static const char * const mem_sigs[] = {
	"LIBFRIDA",
	"frida-agent",
	"frida-gadget",
	"frida_agent",
	"frida-server",
	"re.frida.server",
	"frida:rpc",
	"gum-js-loop",
	"GumScript",
	"linjector",
};

struct arvm_ctx {
	char *buf;
	int len;
	unsigned int gup_flags;
};

static void scrub_frida_signatures(char *buf, int len)
{
	int s, i, sig_len;

	if (!buf || len <= 0)
		return;

	for (s = 0; s < ARRAY_SIZE(mem_sigs); s++) {
		sig_len = strlen(mem_sigs[s]);
		if (sig_len > len)
			continue;
		for (i = 0; i <= len - sig_len; i++) {
			if (memcmp(buf + i, mem_sigs[s], sig_len) == 0) {
				memset(buf + i, 0, sig_len);
				i += sig_len - 1;
			}
		}
	}
}

static int entry_access_remote_vm(struct kretprobe_instance *ri, struct pt_regs *regs)
{
	struct arvm_ctx *ctx = (struct arvm_ctx *)ri->data;

	ctx->buf = (char *)PH_ARG2(regs);
	ctx->len = (int)PH_ARG3(regs);
	ctx->gup_flags = (unsigned int)PH_ARG4(regs);
	return 0;
}

static int ret_access_remote_vm(struct kretprobe_instance *ri, struct pt_regs *regs)
{
	struct arvm_ctx *ctx = (struct arvm_ctx *)ri->data;

	if (!panda_hide_mem)
		return 0;
	if (ctx->gup_flags & FOLL_WRITE)
		return 0;
	if (!ctx->buf || ctx->len <= 0)
		return 0;
	scrub_frida_signatures(ctx->buf, ctx->len);
	return 0;
}

static struct kretprobe krp_access_remote_vm = {
	.kp.symbol_name = "access_remote_vm",
	.handler = ret_access_remote_vm,
	.entry_handler = entry_access_remote_vm,
	.data_size = sizeof(struct arvm_ctx),
	.maxactive = 32,
};

static bool reg_arvm;

int panda_mem_init(void)
{
	int err;

	err = register_kretprobe(&krp_access_remote_vm);
	if (err) {
		pr_warn(PH_TAG "kretprobe access_remote_vm failed: %d\n", err);
		return 0; /* non-fatal: feature soft-disabled */
	}
	reg_arvm = true;
	pr_info(PH_TAG "mem hide installed\n");
	return 0;
}

void panda_mem_exit(void)
{
	if (reg_arvm)
		unregister_kretprobe(&krp_access_remote_vm);
	pr_info(PH_TAG "mem hide uninstalled\n");
}
