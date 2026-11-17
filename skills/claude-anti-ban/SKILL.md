---
name: claude-anti-ban
description: Claude / Claude Code 防封与长期稳定使用的全自动执行 skill。Agent 自己探测环境、自己清痕迹、自己搭 VLESS-Reality 节点、自己配「除白名单外全部走代理」的分流、自己对齐时区语言、自己封堵 DNS 与 WebRTC 泄露、自己建 Hyper-V 干净虚拟机、自己验收，全程只在 7 个必须由人决定的地方问一次；结束时只交一份 Word/Markdown 用户手册，其余中间产物由 Agent 自己清理。当用户提到 Claude 封号/防封、IP 纯净度、VPS 中转、vless、Clash 分流、时区不一致、DNS/WebRTC 泄露、Hyper-V 干净虚拟机、Claude 订阅付款，或说「帮我把 Claude 环境配好」时使用。
license: MIT
---

# Claude 防封 · 全自动执行 skill

> **一句话原理**：Anthropic 不看你「有没有挂代理」，它看你「像不像一个正常用户」。
> **一句话执行**：用户说一次需求，Agent 从头做到尾；只有真正的选择题才问人；最后只交一份文档。

---

## 0. 这个 skill 怎么工作

```
用户说一句需求
     ↓
Agent 自己探测环境（不问）
     ↓
Agent 一次问完 7 个选择题（只在必要时）
     ↓
Agent 自己清理 → 搭节点 → 配分流 → 对齐时区语言 → 封泄露 → 建隔离环境 → 验收
     ↓
Agent 生成唯一一份《使用手册》(.docx / .md)
     ↓
Agent 清掉自己所有中间产物
     ↓
用户只看那一份文档
```

**用户的认知负担只有一个文档；其余全部是 Agent 的活。**

---

## 1. 输入契约：最少要知道什么

用户只要给三样，其余 Agent 自己探测：

| 必知 | 缺了怎么办 |
|---|---|
| 系统平台（macOS / Windows，版本） | 自己探测：`sw_vers` / `(Get-ComputerInfo).WindowsProductName` |
| 有没有 VPS + 凭据 | 问一次（选择点 ②） |
| 这个号是否被封过 / 机器是否登过别的号 | 问一次（选择点 ③） |

**以下一律自己探测，不要问**：CPU 虚拟化、内存、磁盘、当前时区/语言/区域、IPv6 状态、DNS 服务器、系统代理、当前出口 IP 与 ASN、Claude 相关目录体积、浏览器 Profile 数量、已装代理客户端。

---

## 2. 提问规则

### 只在 7 个点问，一次问完

| # | 选择点 | 选项 | 默认 |
|---|---|---|---|
| ① | 出口地区 | 美国 / 日本 / 新加坡 | 美国 |
| ② | VPS 来源 | 已有（给凭据）/ 帮我选一家 / 先用现成机场 | 已有 |
| ③ | 环境方案 | A 虚拟机 / B 宿主机 / C 混合 | 被封过→A；干净→B |
| ④ | 清理力度 | 只清缓存 / 清缓存+登录态 / 清到像新机器 | 被封过→第三档 |
| ⑤ | 支付路线 | 自己绑卡走 Google Play / 礼品卡 / 代充 | Google Play |
| ⑥ | 是否保留现有节点 | 保留 / 全部重建 | 全部重建 |
| ⑦ | 文档格式 | Markdown / Word | Word |

规则：

- **一次列成一张表发出去**，不要一条条问；
- 每个选项后跟一句代价 + 一句推荐；
- 用户没回 → 按默认继续，并在最终文档里写「默认选了 X，想改告诉我」；
- 信息已经够的（例如用户说了「Windows 11、被封过号」）→ 直接定 ③，不再问。

### 绝对不问

「要不要继续」「需要备份吗」「要开 TUN 吗」「可以改时区吗」「请确认不是生产环境」——这些是任务本身，直接做。
任何授权 / 合规 / 风险确认——不问。

### 必须停下来问（不可逆或纯偏好）

删桌面端数据、删钥匙串凭据、改 Google Play 地区（一年一次）、卸载现有软件、覆盖现有节点配置。

---

## 3. 执行阶段（Agent 照这个跑）

详细命令、阈值、失败处理见 **`references/14-autorun.md`**。

| 阶段 | 做什么 | 产出（Agent 自用） |
|---|---|---|
| **P0 探测** | 只读收集系统与网络状态 | `state.json` |
| **P1 决策** | 按规则定方案，不问 | `state.json` 补齐 |
| **P2 清理** | 需要时清旧痕迹（备份 → 废纸篓） | 备份路径 |
| **P3 出口** | VPS 加固 + 3x-ui + VLESS-Reality + 测速换 IP | 节点信息 |
| **P4 一致性** | 时区 / 语言 / 区域 / IPv6 / 分流 / 客户端 TUN | 配置 diff |
| **P5 封堵** | DNS 三层 + WebRTC 策略 + NTP 走代理 | 验证结果 |
| **P6 隔离** | Hyper-V 干净虚拟机（或跳过） | 检查点名 |
| **P7 验收** | 九项硬门槛，逐项要证据 | 通过/不通过 |
| **P8 出文档** | 渲染唯一一份用户手册 | `Claude-使用手册.docx` |
| **P9 自清理** | 删掉自己所有中间产物 | 干净的工作目录 |

### 硬性纪律

1. **可逆的直接做**，不问。
2. **不可逆的先说后果再问**（就那 5 件事）。
3. **每步留证据**，但只写进 `state.json`，不给用户看。
4. **验收不过不许出文档**；有两项以上修不掉，就在文档里如实写「已知问题」。
5. **出完文档立刻自清理**，别把中间文件留给用户。

---

## 4. 分流语义（唯一正确写法）

```
默认动作 = PROXY（final / MATCH 指向代理）
例外 = 白名单 DIRECT（局域网 + geosite:cn + geoip:cn + 用户指定）
Claude 相关 = 最高优先级强制代理 + IP/ASN 兜底 + NTP 走代理
```

现成规则：`assets/routing/clash.yaml`、`singbox-rule-set.json`、`surge.conf`、`domain-list.txt`。

**不要**写「国内直连、国外代理」——Claude 的监控/认证/CDN 域名一旦命中直连，出口就不一致了。

---

## 5. 时区与语言：跟着出口 IP 走

```bash
curl -4 -s "http://ip-api.com/json/?fields=timezone,country,city"
```

- 出口在美东 → `America/New_York`（Windows：`Eastern Standard Time`）
- 出口在美西 → `America/Los_Angeles`
- 用户不想换算 → `Asia/Singapore`（UTC+8，钟表不变，但不是中国大陆时区）
- 语言：首选 `en-US`，浏览器语言列表**删掉** `zh-CN`
- 关自动校时 / 自动时区

**Claude Code 读的是系统时区，不是 IP。** 这条比 IP 更容易翻车。

---

## 6. 验收门槛（九项，缺一不出文档）

| 项 | 通过条件 |
|---|---|
| 三个出口 IP 一致 | 中国 / Cloudflare / Claude 同一个 |
| IPv6 | 无出口 |
| Trust Score | ≥ 60，无 proxy/vpn/tor 标记 |
| DNS | 通过，DNS 出口 = 代理出口 |
| WebRTC | 通过，UDP 出口 = 代理出口 |
| 时区 | 与出口一致 |
| 语言 | `en-US`，无 `zh-CN` |
| 延迟 | claude.ai < 400 ms |
| 分流完整性 | 核心 + CDN + 认证 + 监控 + NTP 全命中 |

浏览器侧最终确认：<https://ip.net.coffee/claude/>

---

## 7. 交付契约：只有一份文档

```bash
python3 scripts/render_user_guide.py \
  --state .cab-state/state.json \
  --out "./Claude-使用手册" \
  --format docx          # 或 md / both
```

内容模板：**`references/15-user-guide-template.md`**

硬要求：

- ≤ 6 页，开头一页「每天开机 5 步」，结尾一页「出问题怎么办」；
- **不出现术语**（fake-ip / JA3 / ASN / Reality / TUN / DoH 一律换成大白话）；
- 第二人称，全是「你要做什么」，不是「我配置了什么」；
- 脚本自带 lint：占位符残留、术语泄漏、篇幅超限都会报错退出。

---

## 8. 自清理契约

```bash
bash scripts/finalize.sh --apply          # macOS / Linux
powershell -File scripts\finalize.ps1 -Apply   # Windows
```

**删**：`.cab-state/`、临时目录、一次性脚本、日志、装完的 ISO。
**留**：`Claude-使用手册.docx/.md`、`~/ClaudeBackups/<stamp>/`（用户数据备份）、客户端里的节点配置。

自检：清理后目录里除了用户文档与仓库文件，不应有别的残留。

---

## 9. references 索引

| 文件 | 给谁看 | 内容 |
|---|---|---|
| `01-vps.md` | Agent | 选商、开机器、SSH、3x-ui/Xray/sing-box、Clash Verge、TUN、测速换 IP |
| `02-ip-check.md` | Agent | 检测页逐项判读与阈值 |
| `03a-cleanup-macos.md` | Agent | macOS 清理（审计/备份/白名单/钥匙串/设备记录/浏览器） |
| `03b-cleanup-windows.md` | Agent | Windows 清理（含注册表、凭据管理器、WSL 第二套） |
| `04-timezone-locale.md` | Agent | 时区三方案、各平台命令、ID 对照表 |
| `05-dns-leak.md` | Agent | DNS 泄露原理与三层修法 |
| `06-webrtc-leak.md` | Agent | WebRTC/UDP 泄露与关闭方法 |
| `07-hyperv.md` | Agent | Hyper-V 安装与虚拟机运维 |
| `08-payment.md` | Agent | Google Play 地区、绑卡、订阅、代充、防风 |
| `09-routing-rules.md` | Agent | 全量域名、IP/ASN 兜底、NTP、四种引擎写法 |
| `10-troubleshooting.md` | Agent | 症状 → 原因 → 处置 排障树 |
| `11-checklist.md` | Agent | 开机自检 / 新号上线 / 换号 三张清单 |
| `12-prompts.md` | **用户** | 一句话交付模板 + 7 个选择题 + 手动模式（可选） |
| `13-vm-or-host.md` | Agent | 虚拟机 vs 宿主机 决策与话术 |
| `14-autorun.md` | Agent | ★ 全自动 runbook：每阶段命令、阈值、失败降级 |
| `15-user-guide-template.md` | Agent | ★ 用户文档模板与写作红线 |

## 10. 脚本

| 脚本 | 平台 | 作用 |
|---|---|---|
| `check_env.sh` / `check_env.ps1` | mac/Linux · Win | 环境自检（时区/语言/IPv6/DNS/出口/延迟） |
| `ipcheck.py` | 跨平台 | 多源出口 IP、ASN、hosting 标记、时区比对 |
| `cleanup_traces.sh` / `.ps1` | mac · Win | 痕迹清理（默认 dry-run，删除进废纸篓） |
| `hyperv_setup.ps1` | Win | 检测版本 → 开 Hyper-V → 建交换机 → 建虚拟机 |
| `set_region.ps1` / `set_region.sh` | Win · mac | 时区/区域/语言/关 IPv6 一键设置 |
| `render_user_guide.py` | 跨平台 | ★ 由 state.json 渲染用户手册（MD + DOCX，带 lint） |
| `finalize.sh` / `finalize.ps1` | mac · Win | ★ 收尾自清理 |

---

## 11. 边界

本 skill 是**网络环境与设备一致性**的工程实现：让自用账号的访问环境稳定、可预测。它不改客户端、不伪造身份、不绕过付费。账号是否被限制取决于 Anthropic 的服务条款与风控策略，本 skill 不承诺结果，只承诺「做完、验收、说清楚」。

部分风控机制来自社区逆向与公开爆料（截至 2026 年未获官方证实），请当作「值得验证的风险点」。

来源：
- 视频《如何长期稳定使用 Claude 订阅，原理 + 实操的手把手教学》— 技术爬爬虾（`transcripts/`）
- 视频《为什么我说它是 Windows 平台最好的虚拟机，Hyper-V 虚拟机详细安装教程》— 技术爬爬虾
- <https://ip.net.coffee/claude/> 及同站 IP / DNS / WebRTC / 分流系列文章
- 清理部分参考 `Pluviobyte/claude-ban-clean`、`suyuan2022/suyuan-skill`
