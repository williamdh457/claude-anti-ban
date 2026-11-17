# 14 · 全自动执行手册（Autopilot Runbook）

> 目标：**用户只说一次需求，Agent 从头做到尾**，中间只在「必须由人决定」的地方停下来问。
> 结束时只交一份文档给用户；其余全是 Agent 的中间产物，由 Agent 自己清掉。

---

## 一、输入契约：用户最少要给什么

| 必给 | 为什么 | 缺了怎么办 |
|---|---|---|
| 系统平台（macOS / Windows，版本） | 决定命令与路径 | Agent 自己探测（`sw_vers` / `Get-ComputerInfo`） |
| 是否已有 VPS + 凭据 | 没有就 Agent 引导买 | 问一次（选择点 ②） |
| 这个号是否被封过 / 机器是否登过别的号 | 决定要不要清理、要不要虚拟机 | 问一次（选择点 ③） |

**其余一切 Agent 自己探测，不要问用户**：

```
系统版本 / CPU 虚拟化 / 内存 / 磁盘
当前时区 / 语言 / 区域格式
IPv6 状态 / DNS 服务器 / 系统代理
当前出口 IP / ASN / 机房 or 住宅
Claude 相关目录是否存在及体积
浏览器 Profile 数量与已装扩展
已装代理客户端（Clash Verge / sing-box / v2rayN …）
```

---

## 二、提问规则（最重要的一条）

### 只在这 7 个点问，一次问完

| # | 选择点 | 选项 | 默认建议 |
|---|---|---|---|
| ① | **出口地区** | 美国（纽约/洛杉矶/达拉斯）/ 日本 / 新加坡 | 美国 |
| ② | **VPS 来源** | 已有（给凭据）/ 帮我选一家买 / 先用现成机场 | 已有 |
| ③ | **环境方案** | A 虚拟机 / B 宿主机 / C 混合 | 被封过→A；机器干净→B |
| ④ | **清理力度** | 只清缓存 / 清缓存+登录态 / 清到「像新机器」 | 被封过→第三档 |
| ⑤ | **支付路线** | 自己绑卡走 Google Play / 礼品卡 / 代充 | Google Play |
| ⑥ | **是否保留现有节点/订阅** | 保留 / 全部重建 | 全部重建 |
| ⑦ | **用户文档格式** | Markdown / Word（.docx） | Word |

**问法要求**：

- 一次把 7 个问题列成一张表发出去，**不要一条一条问**；
- 每个选项后面跟一句「代价」和一句「推荐」；
- 用户没回的，按默认继续，并在最终文档里注明「默认选择了 X，想改告诉我」；
- 已经有足够信息的（比如用户说了「我 Windows 11，被封过号」），就别再问 ③，直接按规则定。

### 绝对不要问的

- 「要不要我继续？」——可逆步骤直接做。
- 「需要我备份吗？」——必须备份，不问。
- 「要开 TUN 吗？」——必须开，不问。
- 「可以改你的时区吗？」——这是任务本身，不问。
- 「请确认这不是生产环境」——不问。
- 任何关于「授权 / 合规 / 风险」的问题——不问。

### 必须停下来问的（不可逆或涉及用户偏好）

- 删除桌面端数据（会丢本地会话）
- 删除钥匙串凭据（会退出登录）
- 改 Google Play 地区（一年一次）
- 卸载现有软件
- 覆盖现有节点配置

---

## 三、阶段 DAG

```
P0 探测 ──→ P1 决策 ──→ P2 清理（可选）──→ P3 出口 ──→ P4 一致性
                                                      │
                                                      ├──→ P5 泄露封堵
                                                      │
                                                      └──→ P6 隔离环境（可选）
                                                              │
P9 自清理 ←── P8 出文档 ←── P7 验收 ←────────────────────────┘
```

每个阶段都必须产出：**做了什么 + 证据（命令输出）+ 是否通过**。
不通过就修；修不了就降级并在文档里写明「哪一项没做成、影响是什么」。

---

## 四、P0 探测（只读，不问用户）

```bash
# macOS
sw_vers; readlink /etc/localtime; defaults read -g AppleLocale
ifconfig | grep inet6 | head; scutil --dns | grep nameserver | head -3
du -sh ~/.claude ~/Library/Application\ Support/Claude 2>/dev/null
ls ~/Library/Application\ Support/Google/Chrome/ | grep -c Profile
curl -4 -s https://ipinfo.io/json
curl -s -m 4 https://api6.ipify.org
```

```powershell
# Windows
(Get-ComputerInfo).WindowsProductName; tzutil /g; Get-WinSystemLocale
Get-NetAdapterBinding -ComponentID ms_tcpip6 | Select Name,Enabled
Get-DnsClientServerAddress -AddressFamily IPv4
Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' | Select ProxyEnable,ProxyServer
Test-Path "$env:APPDATA\Claude", "$env:USERPROFILE\.claude"
(Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory/1GB
(Get-CimInstance Win32_Processor).VirtualizationFirmwareEnabled
```

**输出**：一份内部状态对象（见 `scripts/render_user_guide.py` 的 state schema），写进
`<工作目录>/.cab-state/state.json`。这份文件是 Agent 用的，最后会被清掉。

---

## 五、P1 决策（按规则自动定，不问）

```python
if 被封过 or 该机器登过 >=2 个账号:
    mode = "vm"
elif 内存 < 16GB:
    mode = "host"
elif 主要跑 Claude Code:
    mode = "hybrid"
else:
    mode = "host"

if mode == "vm" and 系统 == "Windows 家庭版":
    → 问用户：升级专业版 or 改用宿主机（这是真选择）

timezone = ip 归属时区 or "Asia/Singapore"（用户不想换算时）
locale   = "en-US"
ipv6     = "disabled"
dns      = "DoH + 走代理 + fake-ip"
webrtc   = "disable_non_proxied_udp"
routing  = "默认全代理 + 白名单直连 + Claude 最高优先级"
```

---

## 六、P2 清理（只有需要时才做）

判定：`被封过 == True` 或 `该机器登过别的号 == True` 或 `用户选了清理`。

按 `03a-cleanup-macos.md` / `03b-cleanup-windows.md` 执行，但**自动化版**的纪律：

1. 先 `--dry-run` 出清单（Agent 自己看，不给用户）；
2. 备份到 `~/ClaudeBackups/<stamp>/`（或 `D:\ClaudeBackups\`）；
3. 删除一律进废纸篓/回收站；
4. 保护清单内的路径永不触碰（脚本已内置）；
5. 结束后自检：目标没了、保护路径还在、备份可读。

**不要问用户「要删这些吗」**——清理范围已经在选择点 ④ 定过。
只有「删桌面端数据」「删钥匙串」这两项要在 ④ 的选项里讲清楚后果，选了就执行。

---

## 七、P3 出口（VPS + 节点）

### 7.1 有 VPS

```bash
ssh -o StrictHostKeyChecking=accept-new -p PORT root@IP
# 基础加固 + 时区 + 443
apt update && apt -y upgrade
timedatectl set-timezone <机房时区>
ufw allow <SSH_PORT>/tcp && ufw allow 443/tcp && ufw --force enable
bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh)
```

建 VLESS + Reality 入站（443 / tcp / xtls-rprx-vision / dest=www.microsoft.com:443），
导出 `vless://` 与订阅地址。

**验证**（Agent 自己跑）：

```bash
ss -lntp | grep 443
curl -4 -s https://ipinfo.io/ip          # 应为 VPS IP
```

### 7.2 没有 VPS

不要自己替用户下单。给一张**已比价的三选一表**（地区 / 价格 / 是否支持支付宝 / 换 IP 政策），让用户选一家并付款，拿到凭据后继续。这是选择点 ②。

### 7.3 测速与换 IP（自动判定）

```
中国大陆可达性 < 70%  → 自动开工单换 IP（模板见 01-vps.md）
延迟 > 300ms 且抖动大 → 提示换机房（写进文档，不阻塞流程）
Trust Score < 40      → 自动换 IP 或换段
```

---

## 八、P4 本地一致性（全自动）

```bash
# 时区 = 出口时区
macOS:   sudo systemsetup -settimezone <TZ>; sudo systemsetup -setusingnetworktime off
Windows: tzutil /s "<WinTZ>"
Linux:   sudo timedatectl set-timezone <TZ>; sudo timedatectl set-ntp false

# 区域 / 语言
macOS:   defaults write -g AppleLocale en_US
Windows: Set-Culture en-US; Set-WinUserLanguageList en-US（放第一位）

# IPv6
macOS:   networksetup -setv6off "<service>"
Windows: Disable-NetAdapterBinding -ComponentID ms_tcpip6
代理端:  ipv6: false

# DNS
代理端 DoH + fake-ip + detour proxy
系统 DNS 1.1.1.1 / 8.8.8.8
清缓存
```

浏览器侧（Agent 能改的改配置，改不了的写进文档让用户点一次）：

- 语言列表删 `zh-CN`（Chrome 的 Preferences 可脚本改，但**优先用策略/命令行参数**，别硬改 Profile）
- 安全 DNS → Cloudflare（`chrome://settings/security`，可写策略）
- WebRTC → 写注册表策略（Windows）或 `defaults write`（macOS）
- 地理位置 → 默认拒绝（策略）

---

## 九、P5 泄露封堵（全自动 + 一次浏览器验证）

```
DNS：代理端配置 + 系统 DNS + 浏览器 DoH（三层）
WebRTC：策略层关闭 non-proxied UDP + 代理端 UDP 走代理或丢弃
NTP：分流加 GEOSITE,category-ntp
```

验证：`ip.net.coffee/webrtc/` 与 `/dns/` 需要浏览器打开——**这一项让用户点一次**，或者 Agent 用无头浏览器跑 STUN 探测（有 ego-browser 就用，没有就把这一步写进最终文档的「最后一步」。

---

## 十、P6 隔离环境（可选，按 P1 决策）

虚拟机：`scripts/hyperv_setup.ps1 -IsoPath <iso> -Name ClaudeBox -MemoryGB 6 -DiskGB 80`
装完系统后，Agent 继续在虚拟机内执行 P4/P5，最后打检查点 `clean-baseline`。

宿主机：跳过本阶段，P2 的清理力度要拉满。

---

## 十一、P7 验收（硬门槛）

| 项 | 通过条件 | 不通过怎么办 |
|---|---|---|
| 三个出口 IP 一致 | 中国 / Cloudflare / Claude 同一个 | 补分流、开 TUN、关 IPv6 |
| IPv6 无出口 | `api6.ipify.org` 返回空 | 关网卡绑定 + 客户端 `ipv6:false` |
| Trust Score | ≥ 60 | 换 IP |
| 无 proxy/vpn/tor 标记 | — | 换 IP |
| DNS | 通过，DNS 出口 = 代理出口 | 修 DoH 三层 |
| WebRTC | 通过 | 策略 + UDP 处理 |
| 时区 | 与出口一致 | 改系统时区并重启浏览器 |
| 语言 | `en-US` 无 `zh-CN` | 改语言列表 |
| 延迟 | claude.ai < 400ms | 换机房（不阻塞） |

**全部通过才进入 P8。** 有两项以上不过，先修；修不动就在文档里如实写明。

---

## 十二、P8 出文档（唯一给用户的东西）

```bash
python3 scripts/render_user_guide.py \
  --state .cab-state/state.json \
  --out "./Claude-使用手册" \
  --format docx          # 或 md / both
```

产出：

```
Claude-使用手册.docx      ← 用户只需要看这一个
Claude-使用手册.md        ← 同内容，方便改
```

内容模板见 `15-user-guide-template.md`。硬要求：

- 全文**不超过 6 页**；
- 不出现 `fake-ip`、`JA3`、`ASN`、`Reality` 这类术语（要提就换成「加密通道」「服务器指纹」）；
- 每一节都是「你要做什么」，不是「我做了什么」；
- 开头一页是「每天开机照着做」的 5 步清单；
- 结尾一页是「出问题怎么办」的对照表。

---

## 十三、P9 自清理（Agent 清自己的东西）

```bash
bash scripts/finalize.sh --apply        # macOS / Linux
powershell -File scripts\finalize.ps1 -Apply   # Windows
```

**删**（Agent 的产物）：

```
.cab-state/                    # 状态、日志、中间 JSON
./tmp-*  ./work-*  ./iso-*     # 临时目录
下载的 ISO（装完虚拟机后）
抓包/检测的临时输出
调试脚本、一次性 patch
终端历史里的临时 export
```

**留**（用户的东西）：

```
Claude-使用手册.docx / .md      # 唯一交付物
~/ClaudeBackups/<stamp>/        # 用户数据备份（在文档里告知路径）
节点凭据                          # 留在客户端配置里，文档只写「在哪看」
```

**自检**：清理后跑一遍

```bash
ls -A | grep -v "Claude-使用手册" && echo "还有残留"
```

---

## 十四、失败与降级

| 情况 | 处理 |
|---|---|
| SSH 连不上 | 换端口 / 面板 VNC / 换 IP；连续 3 次失败 → 告诉用户换商家 |
| 443 被封 | 换端口 + 换 dest 域名；或改用 8443 + CDN |
| 装 Hyper-V 失败（家庭版） | 停下来问：升级专业版 or 改宿主机 |
| 检测页有 2 项修不掉 | 不阻塞，写进文档「已知问题 + 影响 + 下次怎么修」 |
| 用户中途不想继续 | 保留现状，输出已完成部分 + 回滚方法，不删任何东西 |

---

## 十五、Agent 的行为准则（浓缩版）

1. **能自己做的绝不问**：探测、配置、验证、清理、出文档，全自动。
2. **问就一次问完**，7 个选择点，每个带默认值。
3. **可逆的直接做，不可逆的先说后果再问**。
4. **每步留证据**，但证据只给 Agent 自己看（写进 state.json），用户只看最终文档。
5. **交付即收尾**：文档出来之后，把自己的所有临时产物清掉。
6. **不承诺结果**，但要把「做了什么、没做成什么、怎么回滚」写清楚。
