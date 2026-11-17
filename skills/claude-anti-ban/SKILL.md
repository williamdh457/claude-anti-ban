---
name: claude-anti-ban
description: Claude / Claude Code 防封与长期稳定使用 skill。教用户如何把需求讲清楚交给 Agent 执行：从 VPS 面板取 IP/SSH 凭据、让 Agent 清理旧账号痕迹（Windows / macOS 分开）、搭 VLESS-Reality 节点、配置「除白名单外全部走代理」的分流、按出口 IP 对齐时区与语言、封堵 DNS 与 WebRTC 泄露、用 Hyper-V 建干净虚拟机或直接改宿主机（含利弊取舍）、万事达卡绑 Google Pay 订阅与养号节奏。当用户提到 Claude 封号/防封、IP 纯净度、住宅 IP、VPS 中转、vless、Clash 分流、时区不一致、DNS 泄露、WebRTC 泄露、Hyper-V 干净虚拟机、Claude 订阅付款时使用。
license: MIT
---

# Claude 防封 · 稳定使用 skill

> **一句话原理**：Anthropic 不看你「有没有挂代理」，它看你「像不像一个正常用户」。
> 所有动作只服务于一件事——让 **出口 IP、系统时区、语言、DNS、UDP、设备指纹、支付方式** 指向同一个地区、同一个身份、长期不变。

---

## 这个 skill 怎么用

它有两个读者：

| 读者 | 怎么用 |
|---|---|
| **你（用户）** | 读第 1–3 节，照着复制指令发给 Agent。不用懂技术细节。 |
| **Agent（执行方）** | 读第 4 节「执行规范」，按里面的顺序和红线动手。 |

**不要**自己从头配。正确姿势是：**把信息准备好 → 复制指令 → 让 Agent 做 → 按验收表检查。**

---

## 1. 你要先准备的东西（5 分钟）

### 1.1 买一台 VPS，然后从面板取这六项

| 信息 | 在哪找 | 示例 |
|---|---|---|
| **IP 地址** | 面板首页 / 实例详情 | `203.0.113.10` |
| **SSH 端口** | 实例详情，默认 `22` | `22` |
| **用户名** | 一般 `root` | `root` |
| **密码** | 「Root Password」→ 重置 | `Xy9#kL2m...` |
| **操作系统** | 你选的镜像 | `Ubuntu 22.04` |
| **机房地区** | 你选的 Location | `美国 纽约` |

各家面板位置：

- **RackNerd / CloudCone / GreenCloud**：Services → 实例 → 「Root Password」「IP Address」
- **Vultr / DigitalOcean / Linode**：实例详情 → 「Access」
- **Evoxt**：VM 列表 → 「VM Control」→ 「Root Credentials」
- **搬瓦工**：KiwiVM → 「Root password modification」

> 密码看不到就重置一次。**发密码给 Agent 只在本地会话里发**，做完建议再改一次密码。
> 选商、测速、换 IP 的细节见 `references/01-vps.md`。

### 1.2 想清楚三件事

1. 你的系统是 **macOS 还是 Windows**？版本多少？
2. 这个号**被封过吗**？这台机器登过几个 Claude 账号？
3. 你要 **虚拟机** 还是 **宿主机**？（见第 5 节，拿不定就让 Agent 问你）

---

## 2. 六条指令（复制即用）

完整可复制文本在 **`references/12-prompts.md`**，这里只列用途和触发时机：

| # | 指令 | 什么时候发 | 一句话作用 |
|---|---|---|---|
| ① | **体检 + 清理** | 被封过号 / 换号 / 换机 | 先只读审计，再备份，最后把旧账号痕迹移走 |
| ② | **搭 VLESS 节点** | 有 VPS 之后 | SSH 进去装面板、建 Reality 入站、导出订阅 |
| ③ | **分流规则** | 节点能用之后 | 改成「除白名单外全部走代理」，Claude 域名最高优先级 |
| ④ | **时区 / 语言 / DNS / WebRTC** | 出口 IP 定了之后 | 让系统身份跟 IP 对齐，封掉两种泄露 |
| ⑤ | **虚拟机（可选）** | 用户选了方案 A | Hyper-V 建干净 Windows，打检查点 |
| ⑥ | **总验收** | 全部做完 | 十项检查，每项要实际输出 |

### 提要求的四段式（所有指令都按这个写）

```
① 背景：什么系统、什么状态、目标是什么
② 输入：VPS 的 IP/端口/账号/密码、已有配置、要不要保留
③ 动作：按什么顺序做什么，哪些不能动
④ 验收：怎么证明成功，失败怎么回滚
```

**别只说「帮我防封」**——Agent 不知道你的系统、VPS、现状，只能给通用建议。

### 懒人一句话版

```text
帮我配 Claude 防封环境：
1. 我系统是【macOS 14 / Windows 11】，之前【被封过号 / 是新号】
2. VPS：IP【x.x.x.x】，端口【22】，root 密码【xxx】，系统 Ubuntu 22.04
3. 帮我搭 vless 节点，规则用「除白名单外全部走代理」，Claude 域名优先级最高
4. 时区语言按出口 IP 对齐，关 IPv6，防 DNS 和 WebRTC 泄露
5. 先只读检查再动手，每步给我命令和验证方法，别自己决定删东西
```

---

## 3. 五条铁律（你和 Agent 都要守）

1. **先测后开**：每次开机、每次换节点，先跑检测页确认全绿，再打开 Claude。顺序反了，风控已经记了一笔。
2. **一致性 > 单点最优**：美国 IP + 上海时区，比「香港 IP + 香港时区」更危险。
3. **出口独享且稳定**：机房 IP 定下来就别换；频繁跳变 = 账号被盗用画像。
4. **一机一号一环境**：一个账号只在一个干净环境登录，不在多设备间来回切。
5. **慢就是快**：新号先免费养 1–3 个月，再 Pro，再 Max。注册当天冲 Max + 猛刷 API 是最快封号路径。

---

## 4. Agent 执行规范（收到请求后按这个做）

### 4.1 顺序：审计 → 计划 → 确认 → 执行 → 验收 → 报告

1. **只读审计**：列出系统版本、时区、语言、IPv6、DNS、代理状态、Claude 相关路径与体积。**不要先删东西。**
2. **出计划**：要删什么、要改什么、备份到哪、哪些不动。等用户确认。
3. **执行**：按计划做，每步给命令和输出。
4. **验收**：逐项检查，给 ✅/⚠️/❌，附实际命令输出。
5. **报告**：改了什么、删了什么、备份在哪、怎么回滚、哪些没做成及原因。

### 4.2 红线（任何情况下不做）

- 不 `rm -rf`、不 `Remove-Item -Recurse -Force`；删除一律先备份再移入废纸篓/回收站。
- 不动 `~/.claude/projects`、`sessions`、`history.jsonl`、`file-history`、`skills`、`plugins`、`hooks`、`commands`、`agents`、`mcp-servers`、`CLAUDE.md`、`settings.json`，不动任何项目目录和 Git 仓库。
- 不自动 kill 进程；检测到 Claude 在跑就停下告诉用户。
- 不点 Claude 客户端的「重置」（用「终止 → 修复」）。
- 不装用户没要求的软件（宝塔、Docker 面板、内核优化脚本、指纹伪装插件）。
- 不改 `MachineGuid`、不改浏览器 UA、不装「时区伪装」类扩展。
- 不把密码、token、备份文件写进仓库或云同步目录。

### 4.3 分流语义（最容易做错的一条）

```
默认动作 = PROXY（final / MATCH 指向代理）
例外 = 白名单 DIRECT（局域网 + geosite:cn + geoip:cn + 用户指定）
Claude 相关 = 最高优先级强制代理 + IP/ASN 兜底 + NTP 走代理
```

**不要**写成「国内直连、国外代理」——Claude 的监控/认证/CDN 域名一旦命中直连规则，出口就不一致了。
完整规则文件在 `assets/routing/`（Clash / sing-box / Surge / 纯域名列表四种）。

### 4.4 时区与语言：跟着 IP 走

```bash
# 先查出口在哪
curl -4 https://ipinfo.io/json
```

- 出口在美东 → 系统时区 `America/New_York`（Windows：`Eastern Standard Time`）
- 出口在美西 → `America/Los_Angeles`（`Pacific Standard Time`）
- 暂时不想换算 → `Asia/Singapore` 或 `Asia/Taipei`（同为 UTC+8，钟表不变，但不是中国大陆时区）
- 语言：首选 `en-US`，浏览器语言列表**删掉** `zh-CN`（界面语言可保留中文）
- 关「自动设置时区」，否则联网后被打回
- **Claude Code 读的是系统时区，不是 IP。** 这条比 IP 更容易翻车。

细节：`references/04-timezone-locale.md`

### 4.5 两种泄露必须封

| 泄露 | 症状 | 修法 |
|---|---|---|
| **DNS** | 连接 IP 在海外，DNS 查询从本地发出 | 代理端 DoH + `fake-ip` + `detour: proxy`；浏览器安全 DNS；系统 DNS 改 1.1.1.1 |
| **WebRTC / UDP** | 网页通过 STUN 拿到真实 IP | Chrome flag `disable_non_proxied_udp`；Firefox 关 `media.peerconnection`；代理开 TUN、UDP 走代理或丢弃 |

细节：`references/05-dns-leak.md`、`references/06-webrtc-leak.md`

### 4.6 验收（每项都要有实际输出）

```bash
curl -4 https://ipinfo.io/ip
curl -4 https://www.cloudflare.com/cdn-cgi/trace | grep ^ip=
curl -6 -s -m 4 https://ipinfo.io/ip     # 应为空
```

| 项 | 通过标准 |
|---|---|
| 三个出口 IP | 中国 / Cloudflare / Claude 完全一致 |
| IPv6 | 无出口 |
| DNS | 通过，DNS 出口 = 代理出口 |
| WebRTC | 通过，UDP 出口 = 代理出口 |
| 时区 | 与出口一致，无「中国大陆时区」黄标 |
| 语言 | `en-US`，无 `zh-CN` |
| Trust Score | ≥ 60，无 VPN/Proxy/Tor/Crawler 标记 |
| 延迟 | claude.ai < 400 ms |

浏览器侧最终确认：<https://ip.net.coffee/claude/>

---

## 5. 虚拟机还是宿主机：先问用户

**不要替用户决定。** 把利弊摆出来让他选（完整版见 `references/13-vm-or-host.md`）：

```text
A. 虚拟机（Hyper-V）
   好处：封号概率最低、可回滚（检查点）、可复制养小号、宿主机折腾不影响它
   代价：占 6–8 GB 内存 + 80 GB 磁盘；首次搭建约 1 小时；多一层窗口；性能略低

B. 宿主机
   好处：零额外开销、最顺手、性能满血
   代价：历史污染清不干净、不可回滚、一号一机的纪律容易破

C. 混合
   日常聊天用宿主机，Claude Code 和长期任务放虚拟机，共用同一个出口 IP
```

判断映射：

| 情况 | 建议 |
|---|---|
| 被封过 / 登过多个号 / 主要跑 Claude Code / 内存 ≥16 GB | **A** |
| 只网页聊天、机器干净、内存 8 GB | **B** |
| 想日常方便又想长期稳 | **C** |

Hyper-V 完整步骤（ISO 获取、开功能、建虚拟机、增强会话、检查点、Win11 注意项）：`references/07-hyperv.md`

---

## 6. 付款与养号

**路线**：安卓手机 + 美国网络 + Google Play（地区=美国）+ 国内可外币支付的 Mastercard → Claude App 内升级，走 Play 账单。

```text
1. 手机连美国节点（用你日常那个干净出口）
2. Play → 头像 → 设置 → 常规 → 账号和设备偏好设置 → 国家和地区 → 美国（一年只能改一次）
3. Play → 付款和订阅 → 付款方式 → 添加 Mastercard（账单地址填美国，免税州更省）
4. Claude App → 菜单 → 头像 → 升级 → 选 Pro → 走 Play 账单
```

**防风要点**：IP 地区 / Play 地区 / 账单地址三者一致；一张卡只给一个账号；别用虚拟卡、预付卡、接码平台号。

**代充**：省事但密码外泄、卡源不可控（盗刷卡会导致订阅回收 + 连坐）。相对安全的是「美国区 Google Play 礼品卡兑换码」，自己兑换。

**养号节奏**：

| 阶段 | 时间 | 动作 |
|---|---|---|
| 种子 | 第 0 天 | 干净环境注册，**不立刻付费** |
| 养 | 1–3 个月 | 只用网页版，低频自然，不碰 API |
| 转正 | 第 2–4 个月 | 升 Pro，轻度用 Claude Code |
| 稳定 | 再 2–3 个月 | 额度留 20–30% 余量，网页聊天继续用 |
| 扩容 | 稳定后 | 升 Max |
| 兜底 | 全程 | 常备 2–3 个在养的小号 |

> 实测结论：「只能美国白天用」「必须英语对话」没必要。真正要控的是 IP 一致性、环境干净度、额度强度、别来回切号。

细节：`references/08-payment.md`

---

## 7. references 索引

| 文件 | 内容 |
|---|---|
| `references/01-vps.md` | 选商、开机器、SSH、3x-ui/Xray/sing-box 搭建、Clash Verge、TUN、测速换 IP |
| `references/02-ip-check.md` | 检测页每一项的含义与判读标准 |
| `references/03a-cleanup-macos.md` | macOS 痕迹清理（审计/备份/白名单/钥匙串/设备记录/浏览器） |
| `references/03b-cleanup-windows.md` | Windows 痕迹清理（含注册表、凭据管理器、WSL 第二套） |
| `references/04-timezone-locale.md` | 时区三方案、各平台命令、时区 ID 对照表 |
| `references/05-dns-leak.md` | DNS 泄露原理与三层修法 |
| `references/06-webrtc-leak.md` | WebRTC/UDP 泄露与各浏览器关闭方法 |
| `references/07-hyperv.md` | Hyper-V 完整安装与虚拟机运维 |
| `references/08-payment.md` | Google Play 地区、绑卡、订阅、代充、防风 |
| `references/09-routing-rules.md` | 全量分流域名、IP/ASN 兜底、NTP、四种引擎写法 |
| `references/10-troubleshooting.md` | 症状 → 原因 → 处置 排障树 |
| `references/11-checklist.md` | 开机自检 / 新号上线 / 换号 三张清单 |
| `references/12-prompts.md` | **可直接复制的六条指令 + 追问话术** |
| `references/13-vm-or-host.md` | 虚拟机 vs 宿主机 决策与话术 |

## 8. 脚本

| 脚本 | 平台 | 作用 |
|---|---|---|
| `scripts/check_env.sh` | macOS / Linux | 时区/语言/IPv6/DNS/出口/连通性 自检 |
| `scripts/check_env.ps1` | Windows | 同上 + 网卡绑定 + 系统代理 |
| `scripts/ipcheck.py` | 跨平台 | 多源出口 IP、ASN、hosting 标记、时区比对 |
| `scripts/cleanup_traces.sh` | macOS | 痕迹清理（默认 dry-run） |
| `scripts/cleanup_traces.ps1` | Windows | 同上 + 凭据管理器 |
| `scripts/hyperv_setup.ps1` | Windows | 检测版本 → 开 Hyper-V → 建交换机 → 建虚拟机 |
| `scripts/set_region.ps1` | Windows | 时区/区域/语言/关自动时区/关 IPv6 一键设置 |
| `scripts/set_region.sh` | macOS / Linux | 同上 |

```bash
bash scripts/check_env.sh            # 先看现状
python3 scripts/ipcheck.py           # 出口体检
bash scripts/cleanup_traces.sh --dry-run
```

## 9. 边界

本 skill 是**网络环境与设备一致性**的工程手册：让自用账号的访问环境稳定、可预测。它不改客户端、不伪造身份、不绕过付费。账号是否被限制取决于 Anthropic 的服务条款与风控策略，本手册不承诺结果。

文中部分风控机制来自社区逆向与公开爆料（截至 2026 年未获官方证实），请当作「值得验证的风险点」，用检测页自行验证。

来源：
- 视频《如何长期稳定使用 Claude 订阅，原理 + 实操的手把手教学》— 技术爬爬虾（字幕见 `transcripts/`）
- 视频《为什么我说它是 Windows 平台最好的虚拟机，Hyper-V 虚拟机详细安装教程》— 技术爬爬虾
- <https://ip.net.coffee/claude/> 及同站 IP / DNS / WebRTC / 分流系列文章
- 清理部分参考 `Pluviobyte/claude-ban-clean`、`suyuan2022/suyuan-skill`（claude-cleanup）
