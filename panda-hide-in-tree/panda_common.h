/* SPDX-License-Identifier: GPL-2.0 */
#ifndef _PANDA_HIDE_COMMON_H
#define _PANDA_HIDE_COMMON_H

#include <linux/kernel.h>
#include <linux/module.h>
#include <linux/moduleparam.h>
#include <linux/slab.h>
#include <linux/string.h>
#include <linux/uaccess.h>
#include <linux/kprobes.h>
#include <linux/kallsyms.h>
#include <linux/version.h>
#include <linux/sched.h>
#include <linux/fs.h>
#include <linux/dcache.h>
#include <linux/net.h>
#include <linux/in.h>
#include <linux/socket.h>
#include <linux/lsm_hooks.h>
#include <linux/security.h>
#include <linux/seq_file.h>
#include <linux/init.h>
#include <linux/errno.h>
#include <linux/types.h>
#include <net/sock.h>

#define PH_TAG "panda-hide: "

extern bool panda_hide_debugger;
extern bool panda_hide_frida;
extern bool panda_hide_path;
extern bool panda_hide_net;
extern bool panda_hide_mem;

int panda_debugger_init(void);
void panda_debugger_exit(void);

int panda_frida_init(void);
void panda_frida_exit(void);

int panda_mem_init(void);
void panda_mem_exit(void);

int panda_path_kprobe_init(void);
void panda_path_kprobe_exit(void);

bool panda_is_hidden_path(const char *path);
bool panda_is_frida_port(__be16 port_be);
bool panda_is_hidden_comm(const char *comm);

unsigned long panda_kallsyms_lookup_name(const char *name);

#endif /* _PANDA_HIDE_COMMON_H */
