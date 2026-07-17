# Zero-kprobe static panda-hide

## What changed

panda-hide 默认改为 **静态源码补丁**（不再依赖 kprobe 跑主路径）：

| 文件 | 改动点 |
|------|--------|
| `fs/proc/array.c` | TracerPid=0；status 状态 tracing stop→sleeping；stat `t`→`S` |
| `fs/proc/base.c` | `wchan` 的 `ptrace_stop` → `0` |
| `fs/proc/task_mmu.c` | `show_map()` 丢掉 frida/gadget/… maps 行 |
| `fs/exec.c` | `__get_task_comm` 净化线程名 |
| `fs/open.c` | `do_faccessat` / `do_sys_openat2` 对黑名单路径返回 `-ENOENT` |
| `mm/memory.c` | `access_remote_vm` 读路径擦除 Frida 特征串 |
| `security/panda-hide/` | `panda_policy.c` + LSM `socket_connect`/`file_open` |
| `include/linux/panda_hide.h` | 给静态调用点用的 API |

应用器：`scripts/apply-panda-static.py`（幂等，锚点匹配 OSS 5.10）。

## 与 kprobe 版关系

- `CONFIG_PANDA_HIDE_STATIC=y`（默认）
- `CONFIG_PANDA_HIDE_KPROBES` 默认 **n**
- 需要运行时 hook 时再手动打开 kprobe 后端

## 语义

字符串黑名单 / 端口 / 线程名 / 内存特征与上游 kpm-panda-hide **同一集合**。  
connect 仍用原生 LSM（也是零 kprobe）。

## 验证（设备上，CI 不做）

```bash
dmesg | grep panda-hide
# ptrace 时 cat /proc/<pid>/status | grep TracerPid  → 0
# maps 中无 frida-agent
# open frida-gadget 路径 → ENOENT
```
