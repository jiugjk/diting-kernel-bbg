// SPDX-License-Identifier: GPL-2.0
/*
 * Shared helpers for panda-hide in-tree port.
 */
#include "panda_common.h"

bool panda_hide_debugger = true;
bool panda_hide_frida = true;
bool panda_hide_path = true;
bool panda_hide_net = true;
bool panda_hide_mem = true;

module_param_named(debugger, panda_hide_debugger, bool, 0644);
MODULE_PARM_DESC(debugger, "Hide ptrace/TracerPid/tracing-stop state (default: Y)");
module_param_named(frida, panda_hide_frida, bool, 0644);
MODULE_PARM_DESC(frida, "Hide frida maps / thread names (default: Y)");
module_param_named(path, panda_hide_path, bool, 0644);
MODULE_PARM_DESC(path, "Hide frida-related paths via LSM (default: Y)");
module_param_named(net, panda_hide_net, bool, 0644);
MODULE_PARM_DESC(net, "Block connect() to frida ports via LSM (default: Y)");
module_param_named(mem, panda_hide_mem, bool, 0644);
MODULE_PARM_DESC(mem, "Scrub frida signatures from remote VM reads (default: Y)");

/*
 * Android GKI often does not EXPORT_SYMBOL_GPL(kallsyms_lookup_name).
 * For built-in we can call it directly when available; for module builds
 * fall back to kprobe-based lookup of the symbol address.
 */
#if defined(CONFIG_KALLSYMS) && !defined(MODULE)
unsigned long panda_kallsyms_lookup_name(const char *name)
{
	return kallsyms_lookup_name(name);
}
#else
static struct kprobe __maybe_unused kp_lookup = {
	.symbol_name = "kallsyms_lookup_name",
};

typedef unsigned long (*kallsyms_lookup_name_t)(const char *name);

unsigned long panda_kallsyms_lookup_name(const char *name)
{
	static kallsyms_lookup_name_t fn;
	int ret;

	if (!fn) {
		ret = register_kprobe(&kp_lookup);
		if (ret < 0)
			return 0;
		fn = (kallsyms_lookup_name_t)kp_lookup.addr;
		unregister_kprobe(&kp_lookup);
	}
	return fn ? fn(name) : 0;
}
#endif

bool panda_is_hidden_path(const char *path)
{
	static const char * const block_paths[] = {
		"re.frida.server",
		"frida-agent-32.so",
		"frida-agent-64.so",
		"frida-agent.so",
		"frida-gadget",
		"linjector",
	};
	int i;

	if (!path || !*path)
		return false;
	/* Frida memfd paths must pass (same as upstream) */
	if (strstr(path, "/memfd:"))
		return false;

	for (i = 0; i < ARRAY_SIZE(block_paths); i++) {
		if (strstr(path, block_paths[i]))
			return true;
	}
	return false;
}

bool panda_is_frida_port(__be16 port_be)
{
	u16 port = ntohs(port_be);

	return port == 27042 || port == 27043 || port == 23946 || port == 31415;
}

bool panda_is_hidden_comm(const char *comm)
{
	static const char * const ban_names[] = {
		"gum-js-loop",
		"pool-frida",
		"pool-spawner",
		"linjector",
		"gmain",
		"gdbus",
		"frida",
	};
	int i;

	if (!comm)
		return false;
	for (i = 0; i < ARRAY_SIZE(ban_names); i++) {
		if (strstr(comm, ban_names[i]))
			return true;
	}
	return false;
}
