/* SPDX-License-Identifier: GPL-2.0 */
/*
 * Public helpers for CONFIG_PANDA_HIDE static integration sites.
 * Call sites live in fs/proc/*, fs/exec.c, fs/open.c, mm/memory.c, etc.
 */
#ifndef _LINUX_PANDA_HIDE_H
#define _LINUX_PANDA_HIDE_H

#include <linux/types.h>
#include <linux/seq_file.h>

#ifdef CONFIG_PANDA_HIDE

/* Path / maps / comm policy (same string sets as kpm-panda-hide) */
bool panda_hide_path_match(const char *path);
bool panda_hide_map_text_match(const char *text);
bool panda_hide_comm_match(const char *comm);
bool panda_hide_is_frida_port_be16(__be16 port_be);

/* /proc maps: drop newly written region if it matches hide list */
bool panda_hide_seq_region_bad(struct seq_file *m, size_t prev_count);

/* Sanitize thread name buffer in-place */
void panda_hide_sanitize_comm(char *comm, size_t buflen);

/* Scrub Frida signatures in kernel buffer from remote VM read */
void panda_hide_scrub_mem(void *buf, int len);

#else /* !CONFIG_PANDA_HIDE */

static inline bool panda_hide_path_match(const char *path) { return false; }
static inline bool panda_hide_map_text_match(const char *text) { return false; }
static inline bool panda_hide_comm_match(const char *comm) { return false; }
static inline bool panda_hide_is_frida_port_be16(__be16 port_be) { return false; }
static inline bool panda_hide_seq_region_bad(struct seq_file *m, size_t prev_count)
{ return false; }
static inline void panda_hide_sanitize_comm(char *comm, size_t buflen) { }
static inline void panda_hide_scrub_mem(void *buf, int len) { }

#endif /* CONFIG_PANDA_HIDE */

#endif /* _LINUX_PANDA_HIDE_H */
