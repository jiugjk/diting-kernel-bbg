// SPDX-License-Identifier: GPL-2.0
/*
 * LSM: socket_connect only for static mode (path hide is in fs/open.c).
 * file_open kept as defense-in-depth.
 */
#include <linux/kernel.h>
#include <linux/slab.h>
#include <linux/string.h>
#include <linux/lsm_hooks.h>
#include <linux/security.h>
#include <linux/fs.h>
#include <linux/dcache.h>
#include <linux/net.h>
#include <linux/in.h>
#include <linux/socket.h>
#include <linux/sched.h>
#include <linux/panda_hide.h>

#define PH_TAG "panda-hide: "

static int panda_file_open(struct file *file)
{
	char *buf, *p;

	if (!file)
		return 0;
	buf = kmalloc(PATH_MAX, GFP_KERNEL);
	if (!buf)
		return 0;
	p = d_path(&file->f_path, buf, PATH_MAX);
	if (!IS_ERR(p) && panda_hide_path_match(p)) {
		pr_info(PH_TAG "open BLOCKED: %s\n", p);
		kfree(buf);
		return -ENOENT;
	}
	kfree(buf);
	return 0;
}

static int panda_socket_connect(struct socket *sock, struct sockaddr *address,
			       int addrlen)
{
	struct sockaddr_in *in;
	char comm[TASK_COMM_LEN];

	if (!address || address->sa_family != AF_INET)
		return 0;
	if (addrlen < (int)sizeof(struct sockaddr_in))
		return 0;

	in = (struct sockaddr_in *)address;
	if (!panda_hide_is_frida_port_be16(in->sin_port))
		return 0;

	get_task_comm(comm, current);
	if (strstr(comm, "adbd"))
		return 0;

	pr_info(PH_TAG "connect BLOCKED port=%u comm=%s\n",
		ntohs(in->sin_port), comm);
	return -ECONNREFUSED;
}

static struct security_hook_list panda_hooks[] __lsm_ro_after_init = {
	LSM_HOOK_INIT(file_open, panda_file_open),
	LSM_HOOK_INIT(socket_connect, panda_socket_connect),
};

static int __init panda_lsm_init(void)
{
	security_add_hooks(panda_hooks, ARRAY_SIZE(panda_hooks), "panda_hide");
	pr_info(PH_TAG "LSM registered (static-mode companion)\n");
	return 0;
}

#ifdef DEFINE_LSM
DEFINE_LSM(panda_hide) = {
	.name = "panda_hide",
	.init = panda_lsm_init,
};
#else
late_initcall(panda_lsm_init);
#endif
