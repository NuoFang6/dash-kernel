#!/usr/bin/env python3
"""collect-notes.py - merge the repository's development notes into one Markdown file.

The output is a single, LLM-friendly document (default: docs/kernel/DEV_NOTES.md):

  * a high-signal "read this first" preamble with the hard rules that cost us
    the most time (AVB/boot packaging, partition safety, module ABI/KCFI,
    F2FS iostat switch semantics, DroidSpaces scope);
  * a current-state snapshot assembled from versions.env / BUILD_INFO /
    SHA256SUMS instead of trusting old prose;
  * a source manifest with path, size, SHA256 and a status/warning banner;
  * every curated note, in order, with headings demoted below the generated
    section heading and relative links rewritten so they keep working from
    docs/kernel/DEV_NOTES.md.

The source files are never modified.  Run `--check` in CI or before a hand-off
to detect a stale merged document.  Add or reorder notes in SOURCES below.

Usage:
    python3 dash/scripts/collect-notes.py
    python3 dash/scripts/collect-notes.py --check
    python3 dash/scripts/collect-notes.py --list
    python3 dash/scripts/collect-notes.py --stdout
"""

from __future__ import annotations

import argparse
import hashlib
import os
import re
import sys
import time
from dataclasses import dataclass
from pathlib import Path

SCRIPT_VERSION = "1"


@dataclass(frozen=True)
class Note:
    path: str
    title: str
    category: str
    status: str = "current"
    warning: str = ""


# Curated order matters: current/pitfall docs first, then context/requirements,
# then upstream/generic references.  Do not add a whole source tree here; these
# are the notes an engineer or LLM should actually read before touching dash.
SOURCES: tuple[Note, ...] = (
    Note("docs/kernel/README.md", "dash 构建与交付入口", "当前交付", "current"),
    Note("docs/kernel/BOOT_PACKAGING.md", "boot / AVB 封装踩坑与硬规则", "当前交付", "current"),
    Note("docs/kernel/TEST_REPORT.md", "测试报告：静态检查、真机证据与 AVB 复盘", "当前交付", "current"),
    Note("docs/kernel/OPEN_ISSUES.md", "未覆盖项、风险与上游同步评估", "当前交付", "current"),
    Note("docs/kernel/DESIGN.md", "实现路径、与 stock 的差异和回退", "当前交付", "current"),
    Note("docs/kernel/STOCK_PARITY_AUDIT.md", "实机 vs stock 特性核对", "当前交付", "current"),
    Note("docs/kernel/UNRESOLVED_GAPS.md", "未完成项按性能影响排序", "当前交付", "current"),
    Note("docs/kernel/UPSTREAM_NOTES_REVIEW.md", "参考仓库工作笔记核对", "当前交付", "current"),
    Note("docs/kernel/UFS_HYBRID_EVIDENCE.md", "UFS/hybrid/fastdiscard 缺口证据与安全边界", "当前交付", "current"),
    Note(
        "docs/project/NAVIGATION.md",
        "仓库导航、子模块 pin 与资源索引",
        "仓库上下文",
        "context",
        "这是仓库地图，不是实时状态；若与 TEST_REPORT 冲突，以 TEST_REPORT 为准。",
    ),
    Note(
        "docs/project/GAP_RESEARCH.md",
        "缺口调研台账：公开源码/近似来源/结论",
        "仓库上下文",
        "context",
        "这是检索台账，不是构建状态；2026-10-30 状态追加在文末，部分链接只记录未下载。",
    ),
    Note(
        "docs/project/DEVICE_MODULES.md",
        "node_cache / os_cpu_qi 的 stock 行为调查",
        "仓库上下文",
        "context",
        "数值是 stock 运行态历史值；当前自编内核的实测值见 TEST_REPORT §8。",
    ),
    Note(
        "docs/handoff/TASK_BRIEF.md",
        "交接任务书与验收标准（历史输入）",
        "需求",
        "requirements",
        "任务书写于 2026-10-29 交接时（文中“当前 6.6.144/只生成 Image”是旧状态）；本仓库已完成 6.6.118 并实机启动。保留原文追溯，不作为当前执行指令。",
    ),
    Note(
        "handoff/dash-gap-handoff/links/SOURCES.md",
        "来源、pin 与“只记录不下载”的近失链接",
        "需求",
        "reference",
        "来源清单中的 project/dash 描述是交接时状态（6.6.144）；当前实现已切到 6.6.118。",
    ),
    Note(
        "third_party/dash-droidspaces/README.md",
        "dash-droidspaces 项目说明（上游参考）",
        "上游参考",
        "upstream",
        "上游基线 commit 与本机 stock 不完全相同；其 DroidSpaces 配置不是本交接目标。",
    ),
    Note(
        "third_party/dash-droidspaces/patches/README.md",
        "OS4 vendor hooks / CRC / CI 单变量开关（上游参考）",
        "上游参考",
        "upstream",
        "上游 README 的 full-call-site bootloop 与本仓库实测不同；详见 docs/kernel/TEST_REPORT.md §10。",
    ),
    Note(
        "third_party/dash-droidspaces/docs/vendor-boot-v15-changeset.md",
        "vendor_boot v15 逐字节变更记录（上游参考）",
        "上游参考",
        "upstream",
    ),
    Note(
        "third_party/dash-droidspaces/docs/gz-erased-changeset.md",
        "gz/Trusty 被擦除与 nvhe 启动变更（上游参考）",
        "上游参考",
        "upstream",
        "本仓库使用 stock cmdline（kvm-arm.mode=protected），未合入 trusty-rescue/nvhe。",
    ),
    Note(
        "third_party/hyperos-lz4kd/Android_GKI_通用内核定制与LZ4KD实战避坑全指南.md",
        "GKI / LZ4KD 通用避坑指南（外部通用指南）",
        "通用参考",
        "generic",
        "通用指南的 AVB/解锁结论不适用于本机 hidden-unlock；boot 封装以 docs/kernel/BOOT_PACKAGING.md 为准。",
    ),
    Note(
        "third_party/hyperos-lz4kd/README.md",
        "hyperos-lz4kd 项目说明（上游参考）",
        "上游参考",
        "upstream",
        "该 README 在“七、开机”处截断，内容与完整避坑指南重复；保留仅用于记录上游现状。",
    ),
    Note(
        "third_party/susfs4ksu/README.md",
        "SUSFS 上游集成说明（上游参考）",
        "上游参考",
        "upstream",
    ),
)


STATUS_LABEL = {
    "current": "当前交付（优先相信）",
    "context": "仓库上下文（可能有过时状态）",
    "requirements": "需求/验收（设备操作受约束）",
    "reference": "来源索引",
    "upstream": "上游参考（版本可能漂移）",
    "generic": "通用指南（设备差异处不适用）",
}


# These are deliberately short and device-specific.  They are the rules that
# would have prevented the bootloops / false conclusions in this workspace.
HARD_RULES = r"""
1. **不要写 `lk`、`super` 或用户数据。** 只允许在所有者明确授权下写当前
   `boot` 槽位；每次刷入重启后先等所有者确认开机，不要继续自动操作。
2. **boot 镜像必须继承 stock 64MB 分区布局。** 保留 header v4、OEM 签名
   vbmeta、AVB footer，只替换 kernel；不要用 mkbootimg 生成紧凑镜像，不要清零
   AVB 尾部，不要改 `--disable-verity/--disable-verification` 的 flags。
3. **本机 `fastboot boot` 不可用**（返回 `unknown command`）。可回退路径是
   完整备份 + 写当前槽位 `boot_b`，不是 RAM 临时启动。
4. **hidden-unlock 不是普通 Orange State。** 它接受“OEM 签名元数据 + kernel
   hash 不匹配”，但拒绝缺失/损坏的 vbmeta；不要把本机结论套到别的设备。
5. **`init_boot` 已还原为 OS4 官方。** 2026-10-30 将 A/B 两个槽都写回
   OS4.0.3.0 payload 里的 `init_boot`（sha256 `3d2062ae…`）；设备启动、内置
   KSU root 正常。之前的 KernelSU patched 副本仅留作历史回滚，不要再把它
   当原厂镜像。
6. **厂商模块兼容不等于签名有效。** `CONFIG_VENDOR_KO_COMPAT` 跳过了签名、
   vermagic、CRC、namespace、protected-export 检查；只用于自有已解锁设备。
7. **13 个 `android_vh_*` hook 的 TP_PROTO 不能随意改。** KCFI 原型不匹配会在
   首次触发时 `brk #0x8228`；改后必须跑 `verify-os4-kcfi.py` 并再实机验证。
8. **`mmap_lock_init/free` 的 EXPORT 必须在 declaration-only TU**（本仓库
   `drivers/android/dash_os4_decl_exports.c`），否则 genksyms CRC 与 stock
   `os_cpu_qi.ko` 的 `__versions` 不一致，整条 QoS 链拒载。
9. **F2FS 增强 iostat 当前需要两个开关**：`iostat_enable=1` 和
   `en_iostat_enable=1`；只开后者计数为 0。这是已知实现差异，不要误判为没实现。
10. **stock 模块全部加载的判断要看逐名对比**：本机 585 个模块 = 584 个 stock
    非 LKM + 额外 `mkp`；stock `kernelsu` LKM 被内建驱动替代，没有双加载。
11. **SELinux 保持 Enforcing。** 不应为了读 sysfs 关闭 SELinux；root（KSU 域）
    已经能读 node_cache/QoS/F2FS/EROFS 数值。
12. **DroidSpaces 不是本交接内核的目标。** 上游加的 SYSVIPC/POSIX_MQUEUE/
    PID_NS/USER_NS/DEVTMPFS/IP_SET 等容器配置，本 stock-config 内核没有；要跑
    容器必须另建变体并单独验证。
13. **上游 dash-droidspaces 的“call site bootloop”不是本仓库的结论。** 本仓库
    完整 13-hook + 全调用点已实机启动；其 `exp/ksu-*` 分支更像是在查它自己的
    KSU/SUSFS early hang，不要据此删掉本仓库的调用点。
14. **不要相信旧状态行。** `docs/project/NAVIGATION.md` /
    `docs/project/GAP_RESEARCH.md` 保留了 6.6.144 调研痕迹；当前构建/运行结论
    以 `docs/kernel/TEST_REPORT.md`、`dash/out/artifacts/BUILD_INFO`、
    `SHA256SUMS` 为准。
"""


# Optional safety guard: set DASH_SECRET_GUARD in the environment if you want the
# generator to refuse a source file containing a sensitive literal.  Never put a
# password/token in this script or in a merged note.
SECRET_GUARD_ENV = "DASH_SECRET_GUARD"


def repo_root_from_script() -> Path:
    return Path(__file__).resolve().parents[2]


def read_text(path: Path) -> str:
    # Keep original line endings out of the merged document.
    return path.read_text(encoding="utf-8", errors="replace").replace("\r\n", "\n").replace("\r", "\n")


def sha256_text(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def find_title(text: str, fallback: str) -> str:
    for line in text.splitlines():
        s = line.strip()
        if s.startswith("# "):
            return s[2:].strip()
        if s and not s.startswith(("<!--", "---", ">")):
            break
    return fallback


def split_fence_state(line: str, in_fence: bool, fence_char: str, fence_len: int):
    """Return (in_fence, fence_char, fence_len) after a line."""
    m = re.match(r"^ {0,3}(`{3,}|~{3,})", line)
    if not m:
        return in_fence, fence_char, fence_len
    marker = m.group(1)
    char = marker[0]
    length = len(marker)
    if not in_fence:
        return True, char, length
    if char == fence_char and length >= fence_len:
        return False, "", 0
    return in_fence, fence_char, fence_len


def rewrite_link_target(target: str, source_dir: Path, out_dir: Path) -> str:
    if not target:
        return target
    if target.startswith(("http://", "https://", "mailto:", "data:", "#", "/", "//")):
        return target
    if target.startswith("<") and target.endswith(">"):
        return target
    path_part, sep, fragment = target.partition("#")
    if not path_part:
        return target
    candidate = (source_dir / path_part).resolve()
    try:
        rel = os.path.relpath(candidate, out_dir.resolve())
    except ValueError:
        return target
    rel = rel.replace(os.sep, "/")
    return rel + (sep + fragment if sep else "")


LINK_RE = re.compile(r"(!?\[[^\]]*\]\()([^)\s]+)(\))")


def demote_and_rewrite(text: str, source_dir: Path, out_dir: Path) -> tuple[str, str, bool]:
    """Remove the first H1 title, demote remaining headings, rewrite relative links.

    Returns (body, title, repaired_fence).  Fenced code blocks are preserved
    byte-for-byte.  Some upstream notes are truncated by their author and end
    inside an open fence; close it so the next section is not swallowed, and
    report repaired_fence=True to the caller.
    """
    lines = text.splitlines()
    title = ""
    title_index = None
    in_fence = False
    fence_char = ""
    fence_len = 0

    # Find the document title: first H1 before any non-empty non-comment line.
    for i, line in enumerate(lines):
        s = line.strip()
        if not s or s.startswith(("<!--", "---", ">")):
            continue
        if s.startswith("# "):
            title = s[2:].strip()
            title_index = i
        break

    out: list[str] = []
    in_fence = False
    fence_char = ""
    fence_len = 0
    for i, line in enumerate(lines):
        if i == title_index:
            continue
        if not in_fence:
            m = re.match(r"^(#{1,6})(\s+.*)$", line)
            if m:
                level = len(m.group(1))
                new_level = min(6, max(3, level + 1))
                line = "#" * new_level + m.group(2)
        if not in_fence:
            line = LINK_RE.sub(
                lambda m: m.group(1)
                + rewrite_link_target(m.group(2), source_dir, out_dir)
                + m.group(3),
                line,
            )
        out.append(line)
        in_fence, fence_char, fence_len = split_fence_state(
            line, in_fence, fence_char, fence_len
        )

    repaired_fence = False
    if in_fence:
        out.append(fence_char * fence_len)
        repaired_fence = True
    body = "\n".join(out).strip("\n")
    return body, title, repaired_fence


def load_snapshot(root: Path) -> str:
    chunks: list[str] = []
    files = [
        ("版本锁定", "dash/versions.env", "text"),
        ("构建信息", "dash/out/artifacts/BUILD_INFO", "text"),
        ("产物校验和", "dash/out/artifacts/SHA256SUMS", "text"),
        ("boot 校验和", "dash/out/artifacts/boot.img.sha256", "text"),
    ]
    for label, rel, _kind in files:
        path = root / rel
        if not path.is_file():
            chunks.append(f"### {label}\n\n`{rel}` 不存在（构建未完成或产物已清理）。\n")
            continue
        content = read_text(path).strip()
        chunks.append(f"### {label}\n\n来源：`{rel}`\n\n```text\n{content}\n```\n")
    return "\n".join(chunks)


def source_mtime(root: Path, notes: tuple[Note, ...]) -> float:
    mtimes = []
    for note in notes:
        path = root / note.path
        if path.is_file():
            mtimes.append(path.stat().st_mtime)
    return max(mtimes) if mtimes else time.time()


def build_document(root: Path, out_path: Path, notes: tuple[Note, ...]) -> str:
    out_dir = out_path.parent
    missing = [n.path for n in notes if not (root / n.path).is_file()]
    if missing:
        raise SystemExit("missing note source(s):\n  " + "\n  ".join(missing))

    stamp = time.strftime("%Y-%m-%d %H:%M:%S %z", time.localtime(source_mtime(root, notes)))
    entries = []
    total_bytes = 0
    for note in notes:
        path = root / note.path
        raw = path.read_bytes()
        text = raw.decode("utf-8", errors="replace").replace("\r\n", "\n").replace("\r", "\n")
        guard = os.environ.get(SECRET_GUARD_ENV)
        if guard and guard in text:
            raise SystemExit(
                f"refusing to merge {note.path}: it contains ${SECRET_GUARD_ENV}"
            )
        title = note.title or find_title(text, path.stem)
        body, doc_title, repaired_fence = demote_and_rewrite(text, path.parent, out_dir)
        if doc_title and not note.title:
            title = doc_title
        entries.append((note, path, raw, body, title, repaired_fence))
        total_bytes += len(raw)

    lines: list[str] = []
    lines.append("# dash 6.6.118 开发笔记合并包（给 LLM 的避坑包）")
    lines.append("")
    lines.append("<!-- 由 dash/scripts/collect-notes.py 自动生成；不要手改本文件。 -->")
    lines.append("")
    lines.append(f"> 生成时间（源文件最新 mtime）：{stamp}  ")
    lines.append(f"> 覆盖 {len(notes)} 个源，{total_bytes} 字节；脚本版本 {SCRIPT_VERSION}。  ")
    lines.append("> 重新生成：`make notes` 或 `python3 scripts/collect-notes.py`；")
    lines.append("> 校验是否过期：`python3 scripts/collect-notes.py --check`。  ")
    lines.append("> 源文件才是权威；本文件只做汇总，遇到冲突按下面的顺序判断。")
    lines.append("")
    lines.append("## 0. LLM 速读（先看这里）")
    lines.append("")
    lines.append("### 0.1 权威顺序")
    lines.append("")
    lines.append("1. `docs/kernel/TEST_REPORT.md` + `dash/out/artifacts/BUILD_INFO` + 真机实测 = **当前运行事实**。")
    lines.append("2. `docs/kernel/BOOT_PACKAGING.md` = **boot/AVB 封装硬规则**（违反会花屏 bootloop）。")
    lines.append("3. `docs/kernel/OPEN_ISSUES.md` = **剩余缺口和风险**（不要重复声称已解决）。")
    lines.append("4. `docs/kernel/DESIGN.md` = **实现路径与 stock 差异**。")
    lines.append("5. `docs/project/NAVIGATION.md` / `GAP_RESEARCH.md` / `DEVICE_MODULES.md` = 上下文和检索台账，**状态行可能过时**。")
    lines.append("6. `docs/handoff/TASK_BRIEF.md` = 历史交接输入，不是当前执行指令。")
    lines.append("7. `third_party/**` 与通用指南 = 上游/外部参考，**本机实测优先**。")
    lines.append("")
    lines.append("### 0.2 硬规则（踩过的坑）")
    lines.append("")
    lines.extend(HARD_RULES.strip().splitlines())
    lines.append("")
    lines.append("### 0.3 当前状态快照（从文件自动生成，不靠旧 prose）")
    lines.append("")
    lines.append(load_snapshot(root).strip())
    lines.append("")
    lines.append("### 0.4 已知冲突 / 容易误读的地方")
    lines.append("")
    lines.append("- **本机 AVB 特例**：hidden-unlock 接受保留 OEM vbmeta/footer、kernel hash 不匹配的 boot；拒绝缺 vbmeta/改 flags。通用指南里的“解锁后随便刷”不适用于此。")
    lines.append("- **init_boot**：2026-10-30 已把 A/B 都还原为 OS4.0.3.0 官方（sha256 `3d2062ae…`）；之前的 KernelSU patched 副本只作历史回滚。")
    lines.append("- **上游 call-site bootloop**：那是 `kernel_dash_droidspaces` 自己的组合；本仓库完整 13-hook 全调用点已开机。不要据此删调用点。")
    lines.append("- **F2FS iostat**：2026-10-30 已修正为 stock 单开关语义：只开 `en_iostat_enable=1` 即记录；stock `io_lat` 仍由 `iostat_enable` 控制。")
    lines.append("- **F2FS fault report**：`f2fs_fault_report` tracepoint 已补，只在同步 `f2fs_handle_error()` 触发；`/proc/fault_report` 已恢复。")
    lines.append("- **DroidSpaces**：本内核没有 SYSVIPC/POSIX_MQUEUE/PID_NS/USER_NS/DEVTMPFS/IP_SET 等容器配置；容器目标要另建变体。")
    lines.append("- **旧状态**：`docs/project/NAVIGATION.md`/`GAP_RESEARCH.md` 里有 6.6.144/6.6.118 时代文字；当前构建是 6.6.143 #3，见 `BUILD_INFO`。")
    lines.append("- **未补齐**：stock 1860 个 traceiter 全部存在（6.6.143 另有 46 个上游新增，LZ4 已恢复）；剩余是 hybrid UFS、EROFS/F2FS 多桶 iostat、SCSI fastdiscard、UFS 37 文件源、VIP 原始策略等，见 OPEN_ISSUES。")
    lines.append("")
    lines.append("## 源清单（Sources）")
    lines.append("")
    lines.append("| # | 类别 | 标题 | 源文件 | 大小 | SHA256 | 状态/警告 |")
    lines.append("|---|---|---|---|---:|---|---|")
    for i, (note, path, raw, _body, _title, repaired_fence) in enumerate(entries, 1):
        warn = note.warning or STATUS_LABEL.get(note.status, note.status)
        if repaired_fence:
            warn += " 源文件代码围栏未闭合，已在合并稿中补齐。"
        warn = warn.replace("|", "\\|")
        lines.append(
            f"| {i:02d} | {note.category} | {note.title or path.name} | "
            f"[`{note.path}`]({os.path.relpath(path, out_dir).replace(os.sep, '/')}) | "
            f"{len(raw)} | `{sha256_text(raw)[:16]}` | {warn} |"
        )
    lines.append("")
    lines.append("快速跳转：" + " · ".join(
        f"[{i:02d}](#src-{i:02d})" for i in range(1, len(entries) + 1)
    ))
    lines.append("")

    for i, (note, path, raw, body, _title, repaired_fence) in enumerate(entries, 1):
        anchor = f"src-{i:02d}"
        rel = os.path.relpath(path, out_dir).replace(os.sep, "/")
        lines.append("---")
        lines.append("")
        lines.append(f'<a id="{anchor}"></a>')
        lines.append(f"## {i}. {note.title or path.name}")
        lines.append("")
        lines.append(f"> 来源：[`{note.path}`]({rel}) · {len(raw)} 字节 · "
                     f"SHA256 `{sha256_text(raw)}`")
        lines.append(f"> 类别：{note.category} · 状态：{STATUS_LABEL.get(note.status, note.status)}")
        if note.warning:
            lines.append(f"> 注意：{note.warning}")
        if repaired_fence:
            lines.append("> 注意：源文件末尾代码围栏未闭合，生成器已补上关闭围栏；源文件本身可能被截断。")
        lines.append("")
        lines.append(body)
        lines.append("")

    lines.append("---")
    lines.append("")
    lines.append("## 附录 A. 生成器与维护")
    lines.append("")
    lines.append("- 脚本：[`dash/scripts/collect-notes.py`](../../dash/scripts/collect-notes.py)")
    lines.append("- 清单：脚本顶部的 `SOURCES`（按顺序合并；新增笔记请同时更新 README 和本清单）。")
    lines.append("- 幂等：同一组源文件内容/时间不变时，重复运行输出相同；`--check` 只在输出过期时失败。")
    lines.append("- 安全：可用 `DASH_SECRET_GUARD` 环境变量指定敏感串做拒合检查；不会读取设备、不会写源文件。")
    lines.append("")
    return "\n".join(lines).rstrip() + "\n"


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--root", type=Path, default=repo_root_from_script(),
                    help="repository root (default: inferred from script path)")
    ap.add_argument("--output", type=Path, default=Path("docs/kernel/DEV_NOTES.md"),
                    help="output path relative to root (default: docs/kernel/DEV_NOTES.md)")
    ap.add_argument("--check", action="store_true",
                    help="exit 1 if the existing output differs from a fresh render")
    ap.add_argument("--stdout", action="store_true", help="render to stdout instead of writing")
    ap.add_argument("--list", action="store_true", help="list the curated sources and exit")
    args = ap.parse_args(argv)

    root = args.root.resolve()
    if args.list:
        for i, note in enumerate(SOURCES, 1):
            print(f"{i:02d} [{note.status:12s}] {note.path}  # {note.title}")
        return 0

    output = args.output
    if not output.is_absolute():
        output = root / output
    document = build_document(root, output, SOURCES)

    if args.stdout:
        sys.stdout.write(document)
        return 0

    if args.check:
        if not output.is_file():
            print(f"missing merged notes: {output}", file=sys.stderr)
            return 1
        current = output.read_text(encoding="utf-8")
        if current != document:
            print(f"stale merged notes: {output} (run collect-notes.py)", file=sys.stderr)
            return 1
        print(f"up to date: {output}")
        return 0

    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(document, encoding="utf-8")
    print(f"wrote {output} ({len(document)} chars, {len(SOURCES)} sources)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
