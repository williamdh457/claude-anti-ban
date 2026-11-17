# 12 · 怎么向 Agent 提要求（可直接复制的指令库）

> 这份手册的核心不是「你自己动手配」，而是**把需求讲清楚，让 Agent 一次做对**。
> 下面每一块都是可以整段复制给 Agent（Claude Code / Codex / Cursor / 任何能跑命令的 Agent）的指令。
> 把 `【】` 里的内容换成你自己的信息。

---

## 0. 提要求的四段式

任何一条指令都按这个结构写，Agent 的成功率会高一个量级：

```
① 背景：我是什么系统、现在什么状态、目标是什么
② 输入：VPS 的 IP/端口/账号/密码、已有配置、要不要保留
③ 动作：按什么顺序做什么，哪些不能动
④ 验收：做完怎么证明成功，失败怎么回滚
```

**不要**只说「帮我防封」。Agent 不知道你的系统、你的 VPS、你的现状，只能给你通用建议——那没用。

---

## 1. 指令一：先体检，再清理（不清理不给搭节点）

### 1.1 macOS 版

```text
【背景】
我在 macOS 上，之前用这个 Claude 账号被封过（或者：我要换新号）。
系统版本 macOS 【14.x】，芯片 【Apple Silicon / Intel】。
现在要用一台全新的干净环境重新开始，请先体检再清理。

【动作】
第一步：只读审计，不要删任何东西。
请检查并列出：
1) 系统时区、语言、区域格式（命令 + 当前值）
2) IPv6 是否启用、当前出口 IP、DNS 服务器
3) 是否开着代理 / TUN 模式
4) Claude 相关本地数据的位置和体积：
   ~/.claude、~/.claude.json、~/.config/claude、~/.cache/claude
   ~/Library/Application Support/Claude
   ~/Library/Caches/com.anthropic.claudefordesktop*
   ~/Library/Logs/Claude
   钥匙串条目 "Claude Code-credentials"
   Chrome / Safari 里 claude.ai、anthropic.com、claude.com 的站点数据
5) VSCode 里 anthropic 扩展的 globalStorage

第二步：给出清理计划，等我确认。
要求：
- 先完整备份到 ~/ClaudeBackups/<时间戳>/，逐文件 SHA-256 校验
- 删除一律移入废纸篓目录，不要 rm -rf，不要清空废纸篓
- 绝对不要动：~/.claude/projects、sessions、history.jsonl、file-history、
  skills、plugins、hooks、commands、agents、mcp-servers、CLAUDE.md、
  settings.json、任何项目目录和 Git 仓库
- 浏览器数据只清 claude.ai / anthropic.com / claude.com / withpersona.com 的
  Cookie、LocalStorage、IndexedDB、Service Worker、站点权限，
  不要动其他站点，不要删书签和历史
- 不要自动 kill 进程；检测到 Claude 在跑就停下来告诉我

第三步：我说「继续」之后才执行，执行完给我一份报告：
实际删了什么、备份在哪、哪些没删掉、怎么恢复。

【约束】
不要改我的 shell 配置、不要动代理设置（那部分我单独让你做）。
不要碰钥匙串，除非我单独说「删 Claude Code-credentials」。
```

### 1.2 Windows 版

```text
【背景】
我在 Windows 【11】上，之前用这个 Claude 账号被封过（或者：我要换新号）。
系统是 【专业版/家庭版】，装了 Claude 桌面端和 Claude Code。
现在要换一套干净环境，请先体检再清理。

【动作】
第一步：只读审计，不要删任何东西。请列出：
1) Windows 版本、时区（tzutil /g）、区域格式、首选语言
2) IPv6 绑定状态（Get-NetAdapterBinding -ComponentID ms_tcpip6）
3) 当前出口 IP、DNS 服务器、系统代理设置
4) 以下路径是否存在及体积：
   %APPDATA%\Claude
   %LOCALAPPDATA%\AnthropicClaude
   %LOCALAPPDATA%\claude-code
   %USERPROFILE%\.claude
   %USERPROFILE%\.claude.json
   %APPDATA%\Code\User\globalStorage\anthropic.*
   %USERPROFILE%\.vscode\extensions\anthropic.*
5) 凭据管理器里的 Claude Code 条目（cmdkey /list | findstr -i claude）
6) Chrome / Edge 里 claude.ai、anthropic.com、claude.com 的站点数据

第二步：给清理计划，等确认。要求：
- 先备份到 D:\ClaudeBackups\<时间戳>\，做 SHA-256 校验
- 删除一律移到回收站（用 Shell.Application 或 Recycle），不要永久删除
- 不动：%USERPROFILE%\.claude\projects、sessions、history.jsonl、
  skills、plugins、hooks、commands、agents、mcp-servers、CLAUDE.md、
  settings.json、任何项目目录
- 浏览器只清上面几个域名的站点数据，别动书签和历史
- 检测到 Claude 进程在跑就停，不要自动结束（除非我明确说结束）

第三步：我说「继续」才执行，完成后报告：删了什么、备份在哪、怎么恢复。

【约束】
不要卸载 Claude 桌面端（先留着，最后一步再说）。
不要改注册表里与网络无关的项。
```

---

## 2. 指令二：搭 VLESS 节点（把 VPS 交给 Agent）

### 2.1 先教会自己：VPS 信息从哪拿

买完 VPS 后，登录商家面板，找到这几样东西——**这就是你要发给 Agent 的全部输入**：

| 信息 | 在哪找 | 示例 |
|---|---|---|
| **IP 地址** | 面板首页 / 实例详情 / 「IP Address」 | `203.0.113.10` |
| **SSH 端口** | 实例详情，默认 22，有的商家改过 | `22` |
| **用户名** | 一般是 `root`，有的商家给 `ubuntu` | `root` |
| **密码** | 首次开机邮件 / 面板「Root Password」→ 重置 | `Xy9#kL2m...` |
| **操作系统** | 你选的镜像 | `Ubuntu 22.04` |
| **地区** | 你选的机房 | `New York` |

各家的位置（大同小异）：

- **RackNerd / CloudCone / GreenCloud**：Services → 点进实例 → 「Root Password」「IP Address」
- **Vultr / DigitalOcean / Linode**：产品/ Droplets → 实例详情 → 「Access」标签
- **Evoxt**：VM 列表 → 「VM Control」→ 「Root Credentials」
- **搬瓦工**：KiwiVM → 「Root password modification」

> 密码看不到怎么办：面板里都有「重置 root 密码」，重置成新的再复制。
> **不要**把密码贴在公开群里；发给 Agent 是本地会话，风险可控，但做完之后建议改一次密码。

### 2.2 指令：让 Agent 搭节点

```text
【背景】
我租了一台 VPS，要搭一个自用的 VLESS 节点，给 Claude 用。
VPS 信息：
  IP:      【203.0.113.10】
  SSH 端口：【22】
  用户名:  【root】
  密码:    【粘贴密码】
  系统:    【Ubuntu 22.04】
  机房:    【美国 纽约】
我本地是 【macOS 14 / Windows 11】，用 【Clash Verge Rev】。

【动作】
请按顺序做，每步做完告诉我结果：
1) SSH 登录，确认系统版本、CPU、内存、磁盘
2) 基础加固：apt update && upgrade，改 SSH 端口到 【2222】，
   安装 ufw 并只放行 SSH 端口 + 443
3) 把 VPS 时区设为机房所在地（timedatectl set-timezone America/New_York）
4) 安装 3x-ui 面板（bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh)），
   记录面板地址、端口、路径、用户名、密码
5) 在面板里建一个入站：
   协议 vless / 端口 443 / 传输 tcp / 流控 xtls-rprx-vision
   安全 reality / dest www.microsoft.com:443 / serverNames 同域名
   生成 x25519 密钥和 shortId
6) 导出 vless:// 链接和订阅地址，发给我
7) 在 VPS 上验证：ss -lntp 看 443 在听、curl -4 https://ipinfo.io 确认出口
8) 告诉我怎么在 Clash Verge 里导入（要具体到点哪个按钮）

【约束】
- 只开 443 和 SSH 端口，其他端口全关
- 不要装任何我没要求的服务（宝塔、Docker 面板、网站、数据库都不要）
- 不要改内核参数做「优化」
- 每一步命令都贴出来，我要能复现
- 如果 443 被占用或防火墙拦截，先告诉我再改方案

【验收】
给我三条可直接粘贴到本地终端的验证命令，
以及每条命令「应该看到什么」。
```

### 2.3 指令：本地客户端接上

```text
【背景】
节点已经搭好，vless 链接是：【粘贴 vless://...】
我在 【macOS / Windows】，客户端是 Clash Verge Rev，已安装。

【动作】
1) 告诉我怎么把 vless 链接转成 Clash 订阅（在线转换或面板订阅，给具体网址和参数）
2) 告诉我在 Clash Verge 里导入的完整点击路径
3) 帮我改配置文件，加入这几项：
   - ipv6: false
   - TUN / 虚拟网卡模式开启（必须，Claude 桌面端不认系统代理）
   - DNS 用 DoH：https://1.1.1.1/dns-query、https://8.8.8.8/dns-query，
     并让 DNS 查询走代理（不是直连）
   - 节点强制 IPv4、TLS 指纹模拟 chrome
4) 导入我给你的分流规则文件（Claude 专用）
5) 给我验证命令和预期输出

【约束】
不要开「智能分流 / 全球直连」模式。
不要让 UDP 直通（要么走代理，要么丢弃）。
```

---

## 3. 指令三：分流规则——「除白名单外，全部走代理」

这是最容易做错的一步。很多人写「国内直连、国外代理」，结果 Claude 的某个监控域名命中了直连规则，出口不一致。

**正确语义**：

```
默认动作 = 代理（final / MATCH 指向 PROXY）
例外 = 白名单（国内常用服务）走直连
Claude 相关 = 最高优先级，强制代理，且加 IP 段兜底
```

### 3.1 指令

```text
【背景】
我在用 Clash（Mihomo 内核），配置文件在 【路径】。
我要的规则语义是：**除了白名单，其余全部走代理**。
不要用「国内直连、国外代理」这种反向写法。

【动作】
1) 把配置改成：
   - final / MATCH 指向 PROXY（默认全代理）
   - 在最前面插入 Claude 专用规则（我下面给你）
   - 白名单（DIRECT）放在 Claude 规则之后：
     *.cn、geosite:cn、geoip:cn、局域网段、以及我常看的国内站点
2) Claude 专用规则必须包含（一条都不能少）：
   核心：anthropic.com / claude.ai / claude.com / clau.de /
         claudemcpclient.com / claudemcpcontent.com / claudeusercontent.com
   CDN：servd-anthropic-website.b-cdn.net / anthropic.com.cdn.cloudflare.net
   认证：anthropic.auth0.com / anthropic-com.ghost.io
   KYC：withpersona.com / frompersona.com / maps.googleapis.com
   监控：sentry.io / statsigapi.net / browser-intake-us5-datadoghq.com /
         DOMAIN-KEYWORD,datadog / DOMAIN-KEYWORD,sift
   客服：intercom.io / intercomcdn.com / cdn.usefathom.com
   NTP：GEOSITE,category-ntp
   IP 兜底：IP-CIDR,160.79.104.0/21,PROXY,no-resolve
            IP-CIDR6,2607:6bc0::/32,PROXY,no-resolve
            IP-ASN,399358,PROXY,no-resolve
3) 规则顺序：Claude 专用 → 其他自定义 → 白名单 DIRECT → final PROXY
4) 改完给我看 diff，并解释每段的作用

【约束】
- 不要把 Claude 规则写在 geosite 通配规则后面（会被抢先匹配）
- IP-CIDR 必须带 no-resolve
- 不要删我原有的节点和策略组
- 改完提醒我重启客户端

【验收】
给我验证方法：
1) curl -4 https://ipinfo.io/ip 和 curl -4 https://www.cloudflare.com/cdn-cgi/trace 的 ip= 是否一致
2) 怎么确认 claude.ai 走的是代理而不是直连
3) 浏览器检测页要看哪几项
```

### 3.2 白名单怎么定（给 Agent 的参考）

```
DIRECT 白名单建议：
- 局域网：192.168.0.0/16、10.0.0.0/8、172.16.0.0/12、127.0.0.0/8、::1
- 国内：geosite:cn、geoip:cn、geosite:private
- 具体服务：微信、支付宝、银行、公司内网、本地开发（localhost）
- 你自己的 NAS / 打印机 / 路由器管理页

其余一律 PROXY。
```

> 宁可多代理几个国内站（慢一点），也不要让 Claude 的任何域名漏到直连。

---

## 4. 指令四：时区 / 语言 / DNS / WebRTC 一次性对齐

```text
【背景】
出口 IP 在 【美国 纽约】（或者你让我查，先查再定）。
我要让系统时区、语言、DNS、WebRTC 全部跟这个 IP 对齐。

【动作】
1) 先查出口 IP 的归属地和时区（curl ipinfo.io/json），告诉我结果
2) 按结果设置：
   - 系统时区 = 出口所在地时区（macOS: systemsetup -settimezone；
     Windows: tzutil /s）
   - 关闭「自动设置时区 / 自动校时」
   - 系统区域格式 = United States，首选语言 = en-US
     （界面语言可以保留中文，只改「首选语言顺序」和「区域格式」）
   - 浏览器语言列表：删掉 zh-CN，只留 en-US
3) 禁用 IPv6：
   - macOS：网络设置里关，或 networksetup -setv6off
   - Windows：Disable-NetAdapterBinding -ComponentID ms_tcpip6
   - 代理客户端：ipv6: false
4) DNS 防泄露：
   - 代理客户端开 DoH + fake-ip + DNS 走代理
   - 浏览器开「安全 DNS」选 Cloudflare
   - 系统 DNS 改成 1.1.1.1 / 8.8.8.8
   - 清 DNS 缓存
5) WebRTC 防泄露：
   - Chrome/Edge：chrome://flags/#webrtc-ip-handling-policy →
     disable_non_proxied_udp（或写注册表策略）
   - 代理端：UDP 走代理或直接丢弃，不要 UDP 直通
6) 做完让我重启浏览器，然后告诉我怎么验证

【约束】
不要装「时区伪装」「指纹伪装」类插件或扩展。
不要改浏览器 UA。
不要动我的输入法（中文输入法留着没关系）。

【验收】
给我 5 条检查命令 + 预期输出，以及检测页上应该看到什么。
```

---

## 5. 指令五：虚拟机 or 宿主机——先让用户选

这一步**不要替用户决定**，把利弊摆出来让他选。完整对比见 `13-vm-or-host.md`。

### 5.1 让用户选的话术（Agent 直接照读）

```text
在开始之前，你要先选一个方案：

A. 虚拟机方案（推荐长期用）
   做法：在 Hyper-V 里开一台干净 Windows，只装浏览器 + VSCode + Claude 桌面端，
        时区语言跟着出口走，一号一机。
   好处：封号概率最低；环境可回滚（打检查点，30 秒回到干净状态）；
        宿主机上折腾什么都不影响它；想养小号直接复制一份。
   代价：占 6–8 GB 内存 + 80 GB 磁盘；第一次装系统要 40 分钟左右；
        日常用起来多一层窗口，稍不方便；性能比宿主机低一点。

B. 宿主机方案（图方便）
   做法：直接在你现在的系统上配好时区、语言、代理、DNS、WebRTC，
        清掉旧痕迹，一号一机。
   好处：零额外开销，用起来最顺手，Claude Code 直接跑在项目目录里。
   代价：宿主机上装的东西都会成为画像的一部分；环境脏了只能手工清；
        一旦这个号废了，整台机器都要重新收拾。

C. 混合方案（多数人的实际选择）
   日常聊天 / 轻量任务 → 宿主机（但要保持干净）
   Claude Code / 长期挂着跑 → 虚拟机
   两个环境用同一个出口 IP，但不同时登录同一个账号。

你选哪个？选 A 我带你装 Hyper-V；选 B 我直接开始配；选 C 我先配宿主机再建虚拟机。
```

### 5.2 用户选 A 之后的指令

```text
【背景】
我选虚拟机方案。宿主机是 Windows 【11 专业版】，内存 【32】GB，
CPU 【i7-12700】，磁盘剩 【200】GB。
我要在 Hyper-V 里建一台只给 Claude 用的虚拟机。

【动作】
1) 先检查：Windows 版本是否支持 Hyper-V、CPU 虚拟化是否开启、
   内存和磁盘够不够。不够就先告诉我，别硬上。
2) 开启 Hyper-V（Enable-WindowsOptionalFeature -FeatureName Microsoft-Hyper-V-All），
   告诉我什么时候需要重启
3) 引导我下载官方 Windows 10 ISO（Media Creation Tool → 为另一台电脑创建安装介质 → ISO）
4) 建虚拟机：
   名称 ClaudeBox，位置 D:\VMs，第一代，内存 6144 MB（固定，不开动态内存），
   网络 Default Switch，虚拟硬盘 80 GB，挂载 ISO
5) 启动并陪我装系统：版本选专业版、我没有产品密钥、自定义安装、
   区域选 United States、键盘 US、本地账户（不要微软账户）
6) 装完做「干净基线」：
   - 时区 = 出口时区，语言 en-US，关自动时区
   - 关 IPv6
   - 装代理客户端 + 开 TUN + 导入 Claude 分流规则
   - 只装：浏览器、VSCode、Claude 桌面端
   - 浏览器语言只留 en-US、安全 DNS、关 WebRTC
   - 打检查点，命名 clean-baseline
7) 告诉我日常怎么用：怎么复制粘贴、怎么传文件、怎么回滚检查点

【约束】
不要装任何国产安全软件、国产浏览器、云同步输入法、AI 加速器。
不要把宿主机整盘共享进虚拟机。
不要开自动检查点（会撑爆磁盘）。

【验收】
给我一份「虚拟机开机自检清单」，我每次开机照着做。
```

---

## 6. 指令六：总验收（做完必跑）

```text
【背景】
前面几步都做完了，现在做最终验收。

【动作】
请逐项检查并给出 ✅/⚠️/❌：
1) 出口 IP：curl -4 https://ipinfo.io/ip 是什么
2) Cloudflare 出口：curl -4 https://www.cloudflare.com/cdn-cgi/trace 里的 ip= 是什么
3) 两者是否一致
4) IPv6 是否有出口
5) DNS 服务器是谁、是否走代理（dig whoami.ds.akahelp.net）
6) 系统时区 / IP 时区是否一致
7) 语言列表里还有没有 zh-CN
8) WebRTC 是否泄露（告诉我怎么在浏览器里看）
9) claude.ai 和 api.anthropic.com 的延迟
10) Claude 专用分流规则是否生效（挑 3 个域名验证）

然后给我一句话结论：现在能不能打开 claude.ai。

【约束】
不要只说「配置完成」。每一项都要有实际命令输出作为证据。
有 ❌ 的项，告诉我怎么修，不要跳过。
```

---

## 7. 一句话版（懒人用）

如果不想写长指令，至少说清这五件事：

```text
帮我配 Claude 防封环境：
1. 我系统是 【macOS 14 / Windows 11】，之前 【被封过号 / 是新号】
2. VPS 信息：IP 【x.x.x.x】，端口 【22】，root 密码 【xxx】，系统 Ubuntu 22.04
3. 帮我搭 vless 节点，规则用「除白名单外全部走代理」，Claude 域名优先级最高
4. 时区语言按出口 IP 对齐，关 IPv6，防 DNS 和 WebRTC 泄露
5. 先只读检查再动手，每步给我命令和验证方法，别自己决定删东西
```

---

## 8. 追问话术（Agent 做得不对时）

| Agent 的表现 | 你该说 |
|---|---|
| 只说「已配置完成」不给证据 | 「每一项给我实际命令输出，我要看到 IP、时区、DNS 的实际值」 |
| 用了「国内直连、国外代理」 | 「改成默认全代理，白名单例外；Claude 规则放最前面」 |
| 直接 rm -rf 清目录 | 「停。先备份到独立目录并校验，删除一律进废纸篓，不许 rm -rf」 |
| 删了项目文件 / 对话历史 | 「立刻停止，从备份恢复；保护清单见指令一」 |
| 改了时区但没关自动同步 | 「关掉自动设置时区，否则联网后会被改回去」 |
| 只关了系统代理没开 TUN | 「开 TUN/虚拟网卡模式，Claude 桌面端不认系统代理」 |
| 忘了 NTP | 「分流里加 GEOSITE,category-ntp，系统校时会暴露真实时区」 |
| 建议装指纹伪装插件 | 「不要，插件改的只是 JS 层，和系统信号冲突反而更异常」 |
| 让你把密码贴到公开地方 | 「不要，密码只在本地会话里给我」 |

---

## 9. 指令里必须出现的「约束」清单

复制任何指令前，检查有没有这几条（没有就补上）：

- [ ] 先只读审计，出计划，等确认再动手
- [ ] 删除前备份 + 校验，删除进废纸篓
- [ ] 保护清单：projects / sessions / history / skills / hooks / CLAUDE.md / settings.json
- [ ] 不动与任务无关的配置（shell、输入法、其他应用）
- [ ] 每步给命令 + 预期输出
- [ ] 失败怎么回滚
- [ ] 不装额外软件（宝塔、Docker 面板、优化脚本）
- [ ] 密码等敏感信息只在本地会话使用
