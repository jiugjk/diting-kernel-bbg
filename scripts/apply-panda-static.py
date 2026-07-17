#!/usr/bin/env python3
"""
Apply zero-kprobe static panda-hide insertions into a kernel tree.
Uses unique contextual anchors from Xiaomi bsp-diting-s-oss (Linux 5.10).
Idempotent: safe to re-run.
"""
from __future__ import annotations

import sys
from pathlib import Path

MARK_BEGIN = "/* PANDA_HIDE_STATIC_BEGIN */"
MARK_END = "/* PANDA_HIDE_STATIC_END */"


def already(text: str) -> bool:
    return MARK_BEGIN in text


def wrap_block(code: str) -> str:
    return f"{MARK_BEGIN}\n{code}\n{MARK_END}\n"


def ensure_include(text: str, include_line: str = "#include <linux/panda_hide.h>") -> str:
    if include_line in text:
        return text
    # After the last #include in the early header block
    lines = text.splitlines(keepends=True)
    last_inc = -1
    for i, ln in enumerate(lines[:80]):
        if ln.startswith("#include"):
            last_inc = i
    if last_inc < 0:
        return include_line + "\n" + text
    lines.insert(last_inc + 1, include_line + "\n")
    return "".join(lines)


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if old not in text:
        # allow if already patched (marker present near target)
        if MARK_BEGIN in text:
            print(f"  [skip] {label}: already patched or context soft-missing")
            return text
        raise SystemExit(f"[ERROR] {label}: anchor not found")
    if text.count(old) != 1:
        # if multiple, still refuse for safety
        raise SystemExit(f"[ERROR] {label}: anchor not unique (count={text.count(old)})")
    print(f"  [ok] {label}")
    return text.replace(old, new, 1)


def patch_array_c(text: str) -> str:
    text = ensure_include(text)
    # 1) Hide tracing-stop state string in /proc/pid/status
    old = "\tseq_puts(m, \"State:\\t\");\n\tseq_puts(m, get_task_state(p));\n"
    new = (
        "\tseq_puts(m, \"State:\\t\");\n"
        f"\t{MARK_BEGIN}\n"
        "\t{\n"
        "\t\tconst char *ph_state = get_task_state(p);\n"
        "#ifdef CONFIG_PANDA_HIDE\n"
        "\t\tif (!strcmp(ph_state, \"t (tracing stop)\"))\n"
        "\t\t\tph_state = \"S (sleeping)\";\n"
        "#endif\n"
        "\t\tseq_puts(m, ph_state);\n"
        "\t}\n"
        f"\t{MARK_END}\n"
    )
    # When already using marker version, old won't match
    if old in text:
        text = replace_once(text, old, new, "array.c:State line")
    elif "ph_state = get_task_state" not in text:
        raise SystemExit("[ERROR] array.c:State line: unexpected content")

    # 2) TracerPid always report 0
    old = "\tseq_put_decimal_ull(m, \"\\nTracerPid:\\t\", tpid);\n"
    new = (
        f"\t{MARK_BEGIN}\n"
        "#ifdef CONFIG_PANDA_HIDE\n"
        "\ttpid = 0;\n"
        "#endif\n"
        f"\t{MARK_END}\n"
        "\tseq_put_decimal_ull(m, \"\\nTracerPid:\\t\", tpid);\n"
    )
    if "TracerPid" in text and "tpid = 0" not in text.split("TracerPid")[0][-80:]:
        if old in text:
            text = replace_once(text, old, new, "array.c:TracerPid")
        elif f"{MARK_BEGIN}\n#ifdef CONFIG_PANDA_HIDE\n\ttpid = 0;" in text:
            print("  [skip] array.c:TracerPid already")
        else:
            # maybe already inserted before line
            if "tpid = 0" in text and "TracerPid" in text:
                print("  [skip] array.c:TracerPid already-ish")
            else:
                raise SystemExit("[ERROR] array.c:TracerPid anchor missing")

    # 3) do_task_stat: state char t -> S
    old = "\tstate = *get_task_state(task);\n"
    new = (
        "\tstate = *get_task_state(task);\n"
        f"\t{MARK_BEGIN}\n"
        "#ifdef CONFIG_PANDA_HIDE\n"
        "\tif (state == 't')\n"
        "\t\tstate = 'S';\n"
        "#endif\n"
        f"\t{MARK_END}\n"
    )
    if "state == 't'" not in text:
        text = replace_once(text, old, new, "array.c:do_task_stat state")
    else:
        print("  [skip] array.c:do_task_stat state already")
    return text


def patch_base_c(text: str) -> str:
    text = ensure_include(text)
    old = (
        "\twchan = get_wchan(task);\n"
        "\tif (wchan && !lookup_symbol_name(wchan, symname)) {\n"
        "\t\tseq_puts(m, symname);\n"
        "\t\treturn 0;\n"
        "\t}\n"
    )
    new = (
        "\twchan = get_wchan(task);\n"
        "\tif (wchan && !lookup_symbol_name(wchan, symname)) {\n"
        f"\t\t{MARK_BEGIN}\n"
        "#ifdef CONFIG_PANDA_HIDE\n"
        "\t\tif (!strcmp(symname, \"ptrace_stop\")) {\n"
        "\t\t\tseq_putc(m, '0');\n"
        "\t\t\treturn 0;\n"
        "\t\t}\n"
        "#endif\n"
        f"\t\t{MARK_END}\n"
        "\t\tseq_puts(m, symname);\n"
        "\t\treturn 0;\n"
        "\t}\n"
    )
    if "ptrace_stop" not in text:
        text = replace_once(text, old, new, "base.c:proc_pid_wchan")
    else:
        print("  [skip] base.c:proc_pid_wchan already")
    return text


def patch_task_mmu_c(text: str) -> str:
    text = ensure_include(text)
    # Patch show_map to drop hidden regions (exact upstream maps hide semantics)
    old = (
        "static int show_map(struct seq_file *m, void *v)\n"
        "{\n"
        "\tshow_map_vma(m, v);\n"
        "\treturn 0;\n"
        "}\n"
    )
    new = (
        "static int show_map(struct seq_file *m, void *v)\n"
        "{\n"
        f"\t{MARK_BEGIN}\n"
        "#ifdef CONFIG_PANDA_HIDE\n"
        "\tsize_t ph_prev = m->count;\n"
        "#endif\n"
        f"\t{MARK_END}\n"
        "\tshow_map_vma(m, v);\n"
        f"\t{MARK_BEGIN}\n"
        "#ifdef CONFIG_PANDA_HIDE\n"
        "\tif (panda_hide_seq_region_bad(m, ph_prev))\n"
        "\t\tm->count = ph_prev;\n"
        "#endif\n"
        f"\t{MARK_END}\n"
        "\treturn 0;\n"
        "}\n"
    )
    if "panda_hide_seq_region_bad" not in text:
        text = replace_once(text, old, new, "task_mmu.c:show_map")
    else:
        print("  [skip] task_mmu.c:show_map already")

    # Also patch show_smap if present with same pattern
    old2 = (
        "static int show_smap(struct seq_file *m, void *v)\n"
    )
    # optional — only if simple show_map_vma call form exists later; skip if complex
    return text


def patch_exec_c(text: str) -> str:
    text = ensure_include(text)
    old = (
        "char *__get_task_comm(char *buf, size_t buf_size, struct task_struct *tsk)\n"
        "{\n"
        "\ttask_lock(tsk);\n"
        "\tstrncpy(buf, tsk->comm, buf_size);\n"
        "\ttask_unlock(tsk);\n"
        "\treturn buf;\n"
        "}\n"
    )
    new = (
        "char *__get_task_comm(char *buf, size_t buf_size, struct task_struct *tsk)\n"
        "{\n"
        "\ttask_lock(tsk);\n"
        "\tstrncpy(buf, tsk->comm, buf_size);\n"
        "\ttask_unlock(tsk);\n"
        f"\t{MARK_BEGIN}\n"
        "#ifdef CONFIG_PANDA_HIDE\n"
        "\tpanda_hide_sanitize_comm(buf, buf_size);\n"
        "#endif\n"
        f"\t{MARK_END}\n"
        "\treturn buf;\n"
        "}\n"
    )
    if "panda_hide_sanitize_comm" not in text:
        text = replace_once(text, old, new, "exec.c:__get_task_comm")
    else:
        print("  [skip] exec.c:__get_task_comm already")
    return text


def patch_memory_c(text: str) -> str:
    text = ensure_include(text)
    old = (
        "int access_remote_vm(struct mm_struct *mm, unsigned long addr,\n"
        "\t\tvoid *buf, int len, unsigned int gup_flags)\n"
        "{\n"
        "\treturn __access_remote_vm(NULL, mm, addr, buf, len, gup_flags);\n"
        "}\n"
    )
    new = (
        "int access_remote_vm(struct mm_struct *mm, unsigned long addr,\n"
        "\t\tvoid *buf, int len, unsigned int gup_flags)\n"
        "{\n"
        f"\t{MARK_BEGIN}\n"
        "#ifdef CONFIG_PANDA_HIDE\n"
        "\t{\n"
        "\t\tint ph_ret = __access_remote_vm(NULL, mm, addr, buf, len, gup_flags);\n"
        "\t\tif (!(gup_flags & FOLL_WRITE) && buf && len > 0)\n"
        "\t\t\tpanda_hide_scrub_mem(buf, len);\n"
        "\t\treturn ph_ret;\n"
        "\t}\n"
        "#else\n"
        "\treturn __access_remote_vm(NULL, mm, addr, buf, len, gup_flags);\n"
        "#endif\n"
        f"\t{MARK_END}\n"
        "}\n"
    )
    if "panda_hide_scrub_mem" not in text:
        text = replace_once(text, old, new, "memory.c:access_remote_vm")
    else:
        print("  [skip] memory.c:access_remote_vm already")
    return text


def patch_open_c(text: str) -> str:
    text = ensure_include(text)
    # do_faccessat early deny
    old = (
        "static long do_faccessat(int dfd, const char __user *filename, int mode, int flags)\n"
        "{\n"
        "\tstruct path path;\n"
        "\tstruct inode *inode;\n"
        "\tint res;\n"
        "\tunsigned int lookup_flags = LOOKUP_FOLLOW;\n"
        "\tconst struct cred *old_cred = NULL;\n"
        "\n"
        "\tif (mode & ~S_IRWXO)\t/* where's F_OK, X_OK, W_OK, R_OK? */\n"
        "\t\treturn -EINVAL;\n"
    )
    new = (
        "static long do_faccessat(int dfd, const char __user *filename, int mode, int flags)\n"
        "{\n"
        "\tstruct path path;\n"
        "\tstruct inode *inode;\n"
        "\tint res;\n"
        "\tunsigned int lookup_flags = LOOKUP_FOLLOW;\n"
        "\tconst struct cred *old_cred = NULL;\n"
        "\n"
        f"\t{MARK_BEGIN}\n"
        "#ifdef CONFIG_PANDA_HIDE\n"
        "\t{\n"
        "\t\tchar ph_buf[256];\n"
        "\t\tlong ph_n = strncpy_from_user(ph_buf, filename, sizeof(ph_buf));\n"
        "\t\tif (ph_n > 0 && ph_n < (long)sizeof(ph_buf) &&\n"
        "\t\t    panda_hide_path_match(ph_buf))\n"
        "\t\t\treturn -ENOENT;\n"
        "\t}\n"
        "#endif\n"
        f"\t{MARK_END}\n"
        "\n"
        "\tif (mode & ~S_IRWXO)\t/* where's F_OK, X_OK, W_OK, R_OK? */\n"
        "\t\treturn -EINVAL;\n"
    )
    if "do_faccessat" in text and "panda_hide_path_match" not in text.split("do_faccessat")[1][:500]:
        text = replace_once(text, old, new, "open.c:do_faccessat")
    else:
        print("  [skip] open.c:do_faccessat already or soft")

    # do_sys_openat2 after getname
    old = (
        "\ttmp = getname(filename);\n"
        "\tif (IS_ERR(tmp))\n"
        "\t\treturn PTR_ERR(tmp);\n"
        "\n"
        "\tfd = get_unused_fd_flags(how->flags);\n"
    )
    new = (
        "\ttmp = getname(filename);\n"
        "\tif (IS_ERR(tmp))\n"
        "\t\treturn PTR_ERR(tmp);\n"
        "\n"
        f"\t{MARK_BEGIN}\n"
        "#ifdef CONFIG_PANDA_HIDE\n"
        "\tif (tmp->name && panda_hide_path_match(tmp->name)) {\n"
        "\t\tputname(tmp);\n"
        "\t\treturn -ENOENT;\n"
        "\t}\n"
        "#endif\n"
        f"\t{MARK_END}\n"
        "\n"
        "\tfd = get_unused_fd_flags(how->flags);\n"
    )
    if "tmp->name && panda_hide_path_match" not in text:
        text = replace_once(text, old, new, "open.c:do_sys_openat2")
    else:
        print("  [skip] open.c:do_sys_openat2 already")
    return text


PATCHERS = {
    "fs/proc/array.c": patch_array_c,
    "fs/proc/base.c": patch_base_c,
    "fs/proc/task_mmu.c": patch_task_mmu_c,
    "fs/exec.c": patch_exec_c,
    "mm/memory.c": patch_memory_c,
    "fs/open.c": patch_open_c,
}


def main() -> int:
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <kernel_src>", file=sys.stderr)
        return 2
    root = Path(sys.argv[1]).resolve()
    if not (root / "Makefile").exists():
        print("[ERROR] not a kernel tree", file=sys.stderr)
        return 1

    print(f"[+] Applying static panda-hide patches under {root}")
    for rel, fn in PATCHERS.items():
        path = root / rel
        if not path.exists():
            print(f"[ERROR] missing {rel}", file=sys.stderr)
            return 1
        print(f"[*] {rel}")
        original = path.read_text(errors="replace")
        updated = fn(original)
        if updated != original:
            path.write_text(updated)
            print(f"  wrote {rel}")
        else:
            print(f"  unchanged {rel}")
    print("[+] Static patches applied")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
