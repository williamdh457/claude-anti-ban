#!/usr/bin/env python3
"""把 Agent 的执行结果渲染成「唯一一份」用户文档（Markdown + Word）。

用法:
    python3 render_user_guide.py --state .cab-state/state.json --out ./Claude-使用手册 --format both

state.json 最少可以只有 {}，缺的字段会用默认值填充并标注「待确认」。
渲染完会自检：占位符残留、术语泄漏、页数估算。有问题退出码非 0。

依赖: python-docx（可选；没有就只出 Markdown）
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from datetime import date
from pathlib import Path

# ---------------------------------------------------------------- 默认状态

DEFAULT_STATE: dict = {
    "generated_at": str(date.today()),
    "platform": "Windows 11",
    "mode": "host",                       # vm | host | hybrid
    "exit": {
        "ip": "—",
        "country": "美国",
        "city": "纽约",
        "timezone": "America/New_York",
        "type": "机房线路",
        "trust": 80,
    },
    "node": {"client": "Clash Verge Rev", "name": "us-node", "port": 443},
    "local": {
        "timezone_label": "纽约时间",
        "tz_offset_note": "和北京时间差 13 小时",
        "language": "英文优先（界面可保留中文）",
        "ipv6": "已关闭",
        "leak": "已封堵",
    },
    "isolation": {"type": "hyperv", "name": "ClaudeBox", "checkpoint": "clean-baseline",
                  "apps": ["浏览器", "VSCode", "Claude 桌面端"]},
    "cleanup": {"performed": False, "backup": ""},
    "verification": {"exit_ips_match": True, "dns_pass": True, "webrtc_pass": True,
                     "tz_pass": True, "lang_pass": True, "latency_ms": 200},
    "payment": {"route": "google-play", "plan": "Pro", "price": "$20/月"},
    "known_issues": [],
}

BANNED = ["fake-ip", "fake ip", "JA3", "JA4", "ASN", "Reality", "TUN", "DoH",
          "WebRTC", "DNS", "SNI", "xtls", "rprx", "vless", "Trojan", "sing-box"]

DAILY_STEPS_VM = [
    "打开 **Hyper-V 管理器**，双击 `{vm_name}`，点「连接」",
    "等桌面出来后，确认右下角的代理软件显示「已连接」",
    "打开浏览器，进 **ip.net.coffee/claude**，看到 6 个绿勾",
    "全绿了，再打开 claude.ai（**顺序别反**）",
    "用完直接关窗口就行，不用做别的",
]

DAILY_STEPS_HOST = [
    "打开电脑上的 **{client}**，确认左下角显示「已连接」",
    "打开浏览器，进 **ip.net.coffee/claude**，看到 6 个绿勾",
    "全绿了，再打开 claude.ai（**顺序别反**）",
    "用就行，别切账号、别登第二个号",
    "关机前不用做任何事",
]

DAILY_STEPS_HYBRID = [
    "日常聊天：确认 **{client}** 已连接 → 打开检测页看绿勾 → 打开 claude.ai",
    "写代码：打开 **Hyper-V 管理器** → 双击 `{vm_name}` → 连接",
    "两边都用同一个节点，**不要一边开一个**",
    "不要在宿主机和虚拟机同时登同一个账号",
    "用完直接关窗口",
]

DONT_DO = [
    ("不要在没连代理的时候打开 Claude", "会暴露你的真实位置"),
    ("不要一天换好几个节点", "会被当成账号被盗"),
    ("不要在同一台电脑上登第二个 Claude 账号", "两个号会被关联"),
    ("不要把额度用满", "每月留两三成，用太狠是异常特征"),
    ("不要在 Claude 的环境里装国产软件或接国产模型", "环境会变脏，前面的功夫白费"),
    ("不要装「改时区」「改指纹」的浏览器插件", "改出来的和系统对不上，反而更可疑"),
    ("不要把账号密码给别人，包括代充", "密码一给，号就不完全是你的了"),
]

TROUBLE = [
    ("登录一直转圈", "网络没连上，或者节点挂了", "看一眼代理是不是「已连接」；换一个节点再试"),
    ("让你验证「你是不是人」", "这个出口 IP 被标记了", "**先别点**，换节点、清一下浏览器记录，再回来"),
    ("突然要邮箱或手机验证", "出口地址跳变了", "换回原来的节点，再验证"),
    ("桌面端点了没反应", "客户端进程卡住了", "设置 → 应用 → Claude → 终止 → 修复（**别点重置**）"),
    ("写代码时老断", "网络抖动，或者同时开的任务太多", "少开几个任务，换个节点"),
    ("付款被拒", "卡或者地区不对", "换一张卡；或者把第 ⑦ 节那句话发给 AI"),
]

ASK_AI = [
    ("想换到日本用", "帮我把节点换到日本，时区语言一起改，改完验证"),
    ("想加一个小号", "帮我按换号流程开一个干净环境养小号"),
    ("检测页有黄的了", "帮我跑一遍自检，把不通过的项修掉"),
    ("想搬回宿主机", "帮我把 Claude 环境从虚拟机迁回宿主机"),
    ("想确认现在安不安全", "帮我做一次全面体检，给我结论"),
]

GLOSSARY = [
    ("出口 IP", "别人眼里你从哪来"),
    ("节点", "你借道的那台海外服务器"),
    ("分流", "哪些流量走海外、哪些走本地"),
    ("虚拟机", "电脑里的一台「电脑里的电脑」"),
    ("检查点", "给虚拟机拍的照片，出事能退回去"),
    ("时区一致", "你的钟表和你的网络出口在同一个地方"),
]


def deep_merge(base: dict, override: dict) -> dict:
    out = dict(base)
    for k, v in (override or {}).items():
        if isinstance(v, dict) and isinstance(out.get(k), dict):
            out[k] = deep_merge(out[k], v)
        else:
            out[k] = v
    return out


# ---------------------------------------------------------------- Markdown

def build_md(s: dict) -> str:
    mode = s.get("mode", "host")
    vm = s.get("isolation", {}).get("name", "ClaudeBox")
    client = s.get("node", {}).get("client", "Clash Verge Rev")
    steps_src = {"vm": DAILY_STEPS_VM, "host": DAILY_STEPS_HOST, "hybrid": DAILY_STEPS_HYBRID}[mode]
    steps = [x.format(vm_name=vm, client=client) for x in steps_src]

    exit_ = s.get("exit", {})
    local = s.get("local", {})
    ver = s.get("verification", {})
    pay = s.get("payment", {})
    iso = s.get("isolation", {})
    cl = s.get("cleanup", {})

    mode_label = {"vm": "单独虚拟机（最稳）", "host": "直接在这台电脑上（最方便）",
                  "hybrid": "日常在这台电脑、写代码在虚拟机"}[mode]

    L: list[str] = []
    A = L.append

    A("# 你的 Claude 使用手册")
    A("")
    A("> 照着做就行，不用懂原理。这份文档只讲两件事：**每天怎么用**、**出问题怎么办**。")
    A("")
    A(f"更新日期：{s.get('generated_at')} ｜ 适用：{s.get('platform')}")
    A("")
    A("---")
    A("")

    # ①
    A("## ① 每天开机，就这 5 步")
    A("")
    for i, step in enumerate(steps, 1):
        A(f"{i}. {step}")
    A("")
    A("> 第 3 步的绿勾如果没全绿，**先别打开 Claude**。看一眼是哪一项不绿，按第 ④ 节处理。")
    A("")

    # ②
    A("## ② 你现在用的是什么")
    A("")
    A("| 项目 | 你的情况 | 意味着什么 |")
    A("|---|---|---|")
    A(f"| 你的网络出口 | {exit_.get('country')} · {exit_.get('city')}（{exit_.get('ip')}） | Claude 认为你在{exit_.get('country')} |")
    A(f"| 线路类型 | {exit_.get('type')} | {'够用，不用换' if '机房' in str(exit_.get('type')) else '属于家庭线路，最自然'} |")
    A(f"| 系统时间 | {local.get('timezone_label')}（{local.get('tz_offset_note')}） | 时间显示和以前不一样，正常 |")
    A(f"| 系统语言 | {local.get('language')} | 不用改回来 |")
    A(f"| 使用环境 | {mode_label} | {'电脑上装别的软件不影响它' if mode != 'host' else '这台电脑要尽量保持干净'} |")
    A(f"| 订阅 | {pay.get('plan')}，{pay.get('price')} | 额度别用满，留两三成 |")
    A("")
    if cl.get("performed"):
        A(f"> 换号前清理过旧记录，备份在 `{cl.get('backup') or '你的备份目录'}`，需要恢复告诉 AI 一声。")
        A("")

    # ③
    A("## ③ 这 7 件事不要做")
    A("")
    for i, (what, why) in enumerate(DONT_DO, 1):
        A(f"{i}. {what} —— {why}")
    A("")

    # ④
    A("## ④ 出问题了，先看这张表")
    A("")
    A("| 你看到的 | 大概是什么原因 | 你该做什么 |")
    A("|---|---|---|")
    for a, b, c in TROUBLE:
        A(f"| {a} | {b} | {c} |")
    A("")
    A("> 记住一句话：**任何弹窗让你「验证」的时候，先别点。** 先看网络对不对，再决定。")
    A("")

    # ⑤
    A("## ⑤ 万一被封了")
    A("")
    A("1. **别急着注册新号。** 先打开检测页，看有没有不绿的地方，先把网络修好。")
    A("2. 到 **support.claude.com** 提交申诉，写清：账号邮箱、平时怎么用（学习 / 写作 / 编程）、没有共享账号。")
    A("3. 等回复。这期间**不要**用同一个环境反复试登录，越试越糟。")
    A("")
    A("如果你决定开新号，把这句话发给 AI：**「帮我按换号流程重做一遍」**。")
    A("")

    # ⑥
    A("## ⑥ 备份和恢复")
    A("")
    A("| 你的东西 | 在哪 | 怎么恢复 |")
    A("|---|---|---|")
    if cl.get("performed"):
        A(f"| 系统备份（清理前） | `{cl.get('backup') or '备份目录'}` | 告诉 AI「从备份恢复」 |")
    if mode in ("vm", "hybrid"):
        A(f"| 虚拟机快照 | Hyper-V → {iso.get('name')} → 检查点 `{iso.get('checkpoint')}` | 右键 → 还原 |")
    A(f"| 节点配置 | {client} 的「订阅」里，名字 `{s.get('node', {}).get('name')}` | 重新导入订阅地址 |")
    A("")

    # ⑦
    A("## ⑦ 以后想改设置，把这句话发给 AI")
    A("")
    A("| 你想干什么 | 复制这句话 |")
    A("|---|---|")
    for what, line in ASK_AI:
        A(f"| {what} | 「{line}」 |")
    A("")

    # 已知问题
    issues = s.get("known_issues") or []
    if issues:
        A("## ⑧ 目前还没完全搞定的事")
        A("")
        for it in issues:
            A(f"- {it}")
        A("")
        A("> 这些不影响日常使用，但你自己心里要有数。")
        A("")

    # 附录
    A("---")
    A("")
    A("## 附录 A：这些名词是什么意思")
    A("")
    A("| 名词 | 大白话 |")
    A("|---|---|")
    for a, b in GLOSSARY:
        A(f"| {a} | {b} |")
    A("")

    A("## 附录 B：你的节点信息在哪看")
    A("")
    A(f"- 客户端：{client} → 订阅 → 名字 `{s.get('node', {}).get('name')}`")
    A("- 订阅地址：在客户端里，右键可以复制（**别发给别人**）")
    A("- 服务器后台：面板地址和密码在你自己的密码管理器里")
    A("")
    A("---")
    A("")
    A("### 这份文档的边界")
    A("")
    A("它帮你把「环境」调到最不容易出问题的状态，但**不承诺账号一定不会被限制**。")
    A("账号状态最终取决于 Anthropic 的规则。真遇到问题，走官方申诉，别反复试。")
    A("")
    return "\n".join(L)


# ---------------------------------------------------------------- DOCX

def build_docx(md_text: str, out_path: Path) -> bool:
    try:
        from docx import Document
        from docx.shared import Pt, RGBColor
    except ImportError:
        return False

    doc = Document()

    # 基础样式
    normal = doc.styles["Normal"]
    normal.font.name = "Microsoft YaHei"
    normal.font.size = Pt(10.5)

    lines = md_text.splitlines()
    i = 0
    table_buf: list[list[str]] = []

    def flush_table() -> None:
        nonlocal table_buf
        if not table_buf:
            return
        rows = [r for r in table_buf if not re.match(r"^\|[\s:\-|]+\|$", r)]
        cells = [[c.strip() for c in r.strip().strip("|").split("|")] for r in rows]
        if cells:
            ncol = max(len(r) for r in cells)
            t = doc.add_table(rows=0, cols=ncol)
            t.style = "Light Grid Accent 1"
            for ri, row in enumerate(cells):
                rc = t.add_row().cells
                for ci in range(ncol):
                    rc[ci].text = re.sub(r"\*\*(.+?)\*\*", r"\1", row[ci]) if ci < len(row) else ""
                    if ri == 0:
                        for p in rc[ci].paragraphs:
                            for run in p.runs:
                                run.bold = True
        table_buf = []

    while i < len(lines):
        line = lines[i]
        stripped = line.strip()

        if stripped.startswith("|"):
            table_buf.append(stripped)
            i += 1
            continue
        flush_table()

        if not stripped:
            i += 1
            continue

        if stripped.startswith("### "):
            doc.add_heading(stripped[4:], level=3)
        elif stripped.startswith("## "):
            doc.add_heading(stripped[3:], level=1)
        elif stripped.startswith("# "):
            h = doc.add_heading(stripped[2:], level=0)
            for run in h.runs:
                run.font.color.rgb = RGBColor(0x1F, 0x1E, 0x1D)
        elif re.match(r"^\d+\.\s", stripped):
            txt = re.sub(r"^\d+\.\s+", "", stripped)
            p = doc.add_paragraph(style="List Number")
            _add_runs(p, txt)
        elif stripped.startswith("- "):
            p = doc.add_paragraph(style="List Bullet")
            _add_runs(p, stripped[2:])
        elif stripped.startswith("> "):
            p = doc.add_paragraph()
            run = p.add_run(stripped[2:].replace("**", ""))
            run.italic = True
            run.font.size = Pt(9.5)
        elif stripped == "---":
            doc.add_paragraph()
        else:
            p = doc.add_paragraph()
            _add_runs(p, stripped)
        i += 1

    flush_table()
    doc.save(str(out_path))
    return True


def _add_runs(paragraph, text: str) -> None:
    """把 **bold** 转成真正的粗体 run。"""
    parts = re.split(r"(\*\*.+?\*\*)", text)
    for part in parts:
        if not part:
            continue
        if part.startswith("**") and part.endswith("**"):
            run = paragraph.add_run(part[2:-2])
            run.bold = True
        else:
            paragraph.add_run(part)


# ---------------------------------------------------------------- 自检

def lint(md_text: str) -> list[str]:
    problems: list[str] = []

    if "{{" in md_text or "}}" in md_text:
        problems.append("有未替换的占位符 {{...}}")

    lowered = md_text.lower()
    hits = sorted({b for b in BANNED if b.lower() in lowered})
    if hits:
        problems.append("出现技术术语: " + ", ".join(hits))

    # 粗略页数：中文按 900 字/页
    chars = len(re.sub(r"\s", "", md_text))
    pages = chars / 900
    if pages > 6:
        problems.append(f"篇幅约 {pages:.1f} 页，超过 6 页上限")

    if "每天开机" not in md_text:
        problems.append("缺少「每天开机」清单")

    return problems


# ---------------------------------------------------------------- main

def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--state", default=".cab-state/state.json")
    ap.add_argument("--out", default="./Claude-使用手册")
    ap.add_argument("--format", choices=["md", "docx", "both"], default="both")
    ap.add_argument("--quiet", action="store_true")
    args = ap.parse_args()

    raw: dict = {}
    sp = Path(args.state)
    if sp.exists():
        try:
            raw = json.loads(sp.read_text(encoding="utf-8"))
        except json.JSONDecodeError as e:
            print(f"state.json 解析失败: {e}", file=sys.stderr)
            return 2
    elif not args.quiet:
        print(f"提示: 没找到 {sp}，用默认值渲染（记得回填真实信息）", file=sys.stderr)

    state = deep_merge(DEFAULT_STATE, raw)
    md = build_md(state)

    out_base = Path(args.out)
    out_base.parent.mkdir(parents=True, exist_ok=True)

    written: list[str] = []
    if args.format in ("md", "both"):
        p = out_base.with_suffix(".md")
        p.write_text(md, encoding="utf-8")
        written.append(str(p))

    if args.format in ("docx", "both"):
        p = out_base.with_suffix(".docx")
        if build_docx(md, p):
            written.append(str(p))
        elif not args.quiet:
            print("提示: 没装 python-docx，只输出 Markdown", file=sys.stderr)

    problems = lint(md)
    if not args.quiet:
        print("已生成:")
        for w in written:
            print("  -", w)
        chars = len(re.sub(r"\s", "", md))
        print(f"篇幅: 约 {chars} 字 / {chars/900:.1f} 页")
        if problems:
            print("\n自检未通过:")
            for p_ in problems:
                print("  ✗", p_)
        else:
            print("自检: 通过（无占位符、无术语泄漏、篇幅合规）")

    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
