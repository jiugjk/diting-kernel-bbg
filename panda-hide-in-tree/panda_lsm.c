// SPDX-License-Identifier: GPL-2.0
/*
 * LSM hooks — port of openat_hide.c + net_hide.c (native, no KernelPatch)
 *
 * file_open        ~ openat path deny (-ENOENT)
 * socket_connect   ~ connect() frida port deny (-ECONNREFUSED), allow adbd
 */
#include "panda_common.h"
#include <linux/path.h>
#include <linux/cred.h>

static int panda_file_open(struct file *file)
{
	char *buf, *p;

	if (!panda_hide_path || !file)
		return 0;

	buf = kmalloc(PATH_MAX, GFP_KERNEL);
	if (!buf)
		return 0;

	p = d_path(&file->f_path, buf, PATH_MAX);
	if (!IS_ERR(p) && panda_is_hidden_path(p)) {
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

	if (!panda_hide_net || !address)
		return 0;
	if (address->sa_family != AF_INET)
		return 0;
	if (addrlen < (int)sizeof(struct sockaddr_in))
		return 0;

	in = (struct sockaddr_in *)address;
	if (!panda_is_frida_port(in->sin_port))
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
	pr_info(PH_TAG "LSM hooks registered (file_open + socket_connect)\n");
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
