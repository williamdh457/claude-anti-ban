# Claude 防封手册 · claude-anti-ban

> 一套**可执行**的 Claude / Claude Code 长期稳定使用方案。
> 不讲玄学，只讲顺序：**先测 → 再配 → 再登**。
> 附带一个 Agent Skill：把需求讲清楚，让 AI 帮你把环境配好。

<p align="center">
  <img alt="license" src="https://img.shields.io/badge/license-MIT-blue.svg">
  <img alt="platform" src="https://img.shields.io/badge/platform-macOS%20%7C%20Windows-lightgrey.svg">
  <img alt="skill" src="https://img.shields.io/badge/skill-Claude%20Code%20%2F%20Codex%20%2F%20Cursor-green.svg">
</p>

---

## 这个仓库解决什么问题

大多数人「被封」不是因为技术不够，而是因为**画像自相矛盾**：

```
IP 在纽约  ·  系统时区写着 Asia/Shanghai  ·  浏览器语言 zh-CN
DNS 查询从国内发出  ·  WebRTC 泄露真实 IP  ·  出口 IP 一天换三个国家
```

Anthropic 的风控不看你「有没有挂代理」，它看你**像不像一个正常用户**。
所以这个仓库只做一件事：**把出口 IP、系统时区、语言、DNS、UDP、设备指纹、支付方式，全部对齐到同一个地区、同一个身份，并且长期不变。**

---

## 快速开始（3 步）

```bash
git clone https://github.com/<you>/claude-anti-ban.git
cd claude-anti-ban
```

### 1. 先看现状

```bash
bash skills/claude-anti-ban/scripts/check_env.sh        # macOS / Linux
python3 skills/claude-anti-ban/scripts/ipcheck.py       # 出口 IP 体检
```

```powershell
powershell -ExecutionPolicy Bypass -File skills\claude-anti-ban\scripts\check_env.ps1
```

### 2. 打开检测页，确认全绿

👉 <https://ip.net.coffee/claude/>

要绿的是：三个出口 IP 一致、Trust Score ≥ 60、DNS 通过、WebRTC 通过、时区一致、语言匹配。
唯一允许长期为黄的是 **IP 属性 = 机房 IP**。

### 3. 把需求丢给 Agent

复制 [`references/12-prompts.md`](skills/claude-anti-ban/references/12-prompts.md) 里的指令，填上你的 VPS 信息，发给 Claude Code / Codex / Cursor。

> 懒人版：
> ```
> 帮我配 Claude 防封环境：
> 1. 我系统是【macOS 14 / Windows 11】，之前【被封过号 / 是新号】
> 2. VPS：IP【x.x.x.x】，端口【22】，root 密码【xxx】，系统 Ubuntu 22.04
> 3. 帮我搭 vless 节点，规则用「除白名单外全部走代理」，Claude 域名优先级最高
> 4. 时区语言按出口 IP 对齐，关 IPv6，防 DNS 和 WebRTC 泄露
> 5. 先只读检查再动手，每步给我命令和验证方法，别自己决定删东西
> ```

---

## 五条铁律

| # | 铁律 | 为什么 |
|---|---|---|
| 1 | **先测后开** | 每次开机、换节点，先跑检测页再打开 Claude。顺序反了，风控已经记了一笔 |
| 2 | **一致性 > 单点最优** | 美国 IP + 上海时区，比「香港 IP + 香港时区」更危险 |
| 3 | **出口独享且稳定** | 机房 IP 定下来就别换；频繁跳变 = 账号被盗用画像 |
| 4 | **一机一号一环境** | 一个账号只在一个干净环境登录，不在多设备间来回切 |
| 5 | **慢就是快** | 新号先免费养 1–3 个月，再 Pro，再 Max。注册当天冲 Max 是最快封号路径 |

---

## 五个阶段

```
① 痕迹清理（被封过 / 换号才做）
      ↓
② 出口：租 VPS → 搭 VLESS-Reality → 测纯净度
      ↓
③ 一致性：时区 / 语言 / 区域 / IPv6 / 分流
      ↓
④ 泄露封堵：DNS（DoH+走代理）、WebRTC、UDP、NTP
      ↓
⑤ 隔离：Hyper-V 干净虚拟机（或干净的宿主机）
      ↓
⑥ 检测页全绿 → 才打开 claude.ai
      ↓
⑦ 付款（Mastercard → Google Pay）+ 养号
```

---

## 仓库结构

```
claude-anti-ban/
├── README.md                       ← 你在这里
├── docs/
│   ├── 00-原理.md                  风控在看什么
│   ├── 01-快速开始.md              30 分钟上手路径
│   ├── 02-常见问题.md              FAQ
│   └── 03-术语表.md                TUN / fake-ip / Reality / ASN …
├── skills/
│   └── claude-anti-ban/
│       ├── SKILL.md                ★ Agent 可直接加载的 skill
│       ├── references/
│       │   ├── 01-vps.md           选商、开机器、搭节点、Clash Verge
│       │   ├── 02-ip-check.md      检测页逐项判读
│       │   ├── 03a-cleanup-macos.md
│       │   ├── 03b-cleanup-windows.md
│       │   ├── 04-timezone-locale.md
│       │   ├── 05-dns-leak.md
│       │   ├── 06-webrtc-leak.md
│       │   ├── 07-hyperv.md
│       │   ├── 08-payment.md
│       │   ├── 09-routing-rules.md
│       │   ├── 10-troubleshooting.md
│       │   ├── 11-checklist.md
│       │   ├── 12-prompts.md       ★ 可直接复制的指令库
│       │   └── 13-vm-or-host.md    虚拟机 vs 宿主机
│       ├── scripts/                自检 / 清理 / Hyper-V / 区域设置
│       └── assets/routing/         四种引擎的分流规则
└── transcripts/                    两个参考视频的校对字幕
```

---

## 脚本一览

| 脚本 | 平台 | 作用 |
|---|---|---|
| `check_env.sh` | macOS / Linux | 时区 / 语言 / IPv6 / DNS / 出口 / 延迟 自检 |
| `check_env.ps1` | Windows | 同上 + 网卡绑定 + 系统代理 |
| `ipcheck.py` | 跨平台 | 多源出口 IP、ASN、hosting 标记、时区比对 |
| `cleanup_traces.sh` | macOS | 痕迹清理（默认 dry-run，删除进废纸篓） |
| `cleanup_traces.ps1` | Windows | 同上 + 凭据管理器 |
| `hyperv_setup.ps1` | Windows | 检测版本 → 开 Hyper-V → 建交换机 → 建虚拟机 |
| `set_region.ps1` / `.sh` | Windows / macOS | 时区 / 区域 / 语言 / 关 IPv6 一键设置 |

所有清理脚本**默认 dry-run**，删除一律先备份再进废纸篓/回收站，保护清单内的路径永不触碰。

---

## 分流规则（拿来即用）

`skills/claude-anti-ban/assets/routing/`

| 文件 | 引擎 |
|---|---|
| `clash.yaml` | Clash / Mihomo / Stash |
| `singbox-rule-set.json` | sing-box |
| `surge.conf` | Surge / Loon / Quantumult X |
| `domain-list.txt` | 任意工具 |

语义只有一条：**默认全部走代理，白名单例外；Claude 域名优先级最高，并加 IP/ASN 兜底 + NTP 走代理。**

---

## 虚拟机还是宿主机？

不替你决定，把利弊摆出来：

| | 虚拟机（Hyper-V） | 宿主机 |
|---|---|---|
| 防封 | ★★★★★ | ★★★ |
| 便利 | ★★ | ★★★★★ |
| 性能 | ★★★ | ★★★★★ |
| 可回滚 | ✅ 检查点 | ❌ |
| 首次搭建 | 40–60 min | 20 min |
| 适合 | 被封过 / 长期跑 Code / 内存 ≥16 GB | 只网页聊天 / 机器干净 / 内存 8 GB |

详见 [`13-vm-or-host.md`](skills/claude-anti-ban/references/13-vm-or-host.md)。

---

## 付款路线

```
安卓手机 + 美国网络 + Google Play（地区=美国）+ 国内可外币支付的 Mastercard
   → Claude App → 菜单 → 头像 → 升级 → 走 Play 账单 → 先买 Pro
```

防风要点：**IP 地区 / Play 地区 / 账单地址三者一致**；一张卡只给一个账号；别用虚拟卡、预付卡、接码平台号。
详见 [`08-payment.md`](skills/claude-anti-ban/references/08-payment.md)。

---

## 怎么把这个 skill 装进你的 Agent

```bash
# Claude Code（项目级）
mkdir -p .claude/skills
cp -r skills/claude-anti-ban .claude/skills/

# 或用户级
cp -r skills/claude-anti-ban ~/.claude/skills/
```

之后在会话里说「用 claude-anti-ban 帮我配环境」即可加载。

---

## 常见问题（摘）

| 问题 | 答案 |
|---|---|
| 机房 IP 一定被封吗？ | 不是。独享 + 固定 + 其他项全绿，用一年没问题 |
| 只改 IP 就够了吗？ | 不够。时区、语言、DNS、WebRTC 任意一项矛盾都会抵消 |
| 时区改成新加坡可以吗？ | 可以。同为 UTC+8，钟表不变，但不是中国大陆时区 |
| 清理完痕迹就安全了？ | 不是。支付卡、手机号、邮箱、硬件指纹清不掉，得「换」 |
| 一定要虚拟机吗？ | 不一定，但被封过、要长期跑 Claude Code 就建议上 |
| 「只能美国白天用」？ | 没必要。中国作息 + 中文对话实测没问题 |

完整 FAQ：[`docs/02-常见问题.md`](docs/02-常见问题.md)

---

## 参考与致谢

- 视频《如何长期稳定使用 Claude 订阅，原理 + 实操的手把手教学》— 技术爬爬虾（[字幕校对](transcripts/video-1-claude-stable.md)）
- 视频《为什么我说它是 Windows 平台最好的虚拟机，Hyper-V 虚拟机详细安装教程》— 技术爬爬虾（[字幕校对](transcripts/video-2-hyperv.md)）
- [ip.net.coffee/claude](https://ip.net.coffee/claude/) — IP 纯净度 / DNS / WebRTC / 时区指纹检测，以及其 IP 检测、域名分流系列文章
- 清理部分思路参考 [Pluviobyte/claude-ban-clean](https://github.com/Pluviobyte/claude-ban-clean)、[suyuan2022/suyuan-skill](https://github.com/suyuan2022/suyuan-skill)

## 边界

本仓库是**网络环境与设备一致性**的工程手册：让自用账号的访问环境稳定、可预测。它不修改客户端、不伪造身份、不绕过付费。账号是否被限制取决于 Anthropic 的服务条款与风控策略，本仓库不承诺任何结果。

文中部分风控机制来自社区逆向与公开爆料（截至 2026 年未获官方证实），请当作「值得验证的风险点」，用检测页自行验证。

## License

[MIT](LICENSE)
