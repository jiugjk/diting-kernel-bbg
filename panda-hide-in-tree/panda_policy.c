// SPDX-License-Identifier: GPL-2.0
/*
 * Policy helpers shared by static call-site patches.
 * String lists mirror P4nda0s/kpm-panda-hide exactly.
 */
#include <linux/kernel.h>
#include <linux/string.h>
#include <linux/seq_file.h>
#include <linux/in.h>
#include <linux/panda_hide.h>

bool panda_hide_path_match(const char *path)
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
	if (strstr(path, "/memfd:"))
		return false;
	for (i = 0; i < ARRAY_SIZE(block_paths); i++) {
		if (strstr(path, block_paths[i]))
			return true;
	}
	return false;
}
EXPORT_SYMBOL_GPL(panda_hide_path_match);

bool panda_hide_map_text_match(const char *text)
{
	static const char * const block_str[] = {
		"frida", "gadget", "linjector", "gmain",
	};
	int i;

	if (!text)
		return false;
	for (i = 0; i < ARRAY_SIZE(block_str); i++) {
		if (strstr(text, block_str[i]))
			return true;
	}
	return false;
}
EXPORT_SYMBOL_GPL(panda_hide_map_text_match);

bool panda_hide_comm_match(const char *comm)
{
	static const char * const ban_names[] = {
		"gum-js-loop", "pool-frida", "pool-spawner",
		"linjector", "gmain", "gdbus", "frida",
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
EXPORT_SYMBOL_GPL(panda_hide_comm_match);

bool panda_hide_is_frida_port_be16(__be16 port_be)
{
	u16 port = ntohs(port_be);

	return port == 27042 || port == 27043 || port == 23946 || port == 31415;
}
EXPORT_SYMBOL_GPL(panda_hide_is_frida_port_be16);

bool panda_hide_seq_region_bad(struct seq_file *m, size_t prev_count)
{
	char *start;
	size_t new_len;
	char saved;
	bool bad;

	if (!m || !m->buf || m->count < prev_count)
		return false;
	start = m->buf + prev_count;
	new_len = m->count - prev_count;
	if (!new_len)
		return false;

	/* Temporarily NUL-terminate newly written slice (upstream technique) */
	saved = start[new_len];
	start[new_len] = '\0';
	bad = panda_hide_map_text_match(start);
	start[new_len] = saved;
	return bad;
}
EXPORT_SYMBOL_GPL(panda_hide_seq_region_bad);

void panda_hide_sanitize_comm(char *comm, size_t buflen)
{
	static const char fake[] = "binder";
	size_t fake_len = sizeof(fake) - 1;
	size_t len;

	if (!comm || !buflen)
		return;
	if (!panda_hide_comm_match(comm))
		return;
	len = strnlen(comm, buflen);
	if (len >= fake_len) {
		memcpy(comm, fake, fake_len);
		if (fake_len < buflen)
			comm[fake_len] = '\0';
	} else if (len) {
		memcpy(comm, fake, len);
		comm[len] = '\0';
	}
}
EXPORT_SYMBOL_GPL(panda_hide_sanitize_comm);

void panda_hide_scrub_mem(void *buf, int len)
{
	static const char * const mem_sigs[] = {
		"LIBFRIDA", "frida-agent", "frida-gadget", "frida_agent",
		"frida-server", "re.frida.server", "frida:rpc",
		"gum-js-loop", "GumScript", "linjector",
	};
	char *p = buf;
	int s, i, sig_len;

	if (!p || len <= 0)
		return;
	for (s = 0; s < ARRAY_SIZE(mem_sigs); s++) {
		sig_len = strlen(mem_sigs[s]);
		if (sig_len > len)
			continue;
		for (i = 0; i <= len - sig_len; i++) {
			if (memcmp(p + i, mem_sigs[s], sig_len) == 0) {
				memset(p + i, 0, sig_len);
				i += sig_len - 1;
			}
		}
	}
}
EXPORT_SYMBOL_GPL(panda_hide_scrub_mem);
