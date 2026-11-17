# 04 · 时区 / 语言 / 地区一致性

> 目标：让「出口 IP 所在地」「系统时区」「浏览器语言」「NTP 校时」四个信号指向同一个地区。
> 这一条是整份手册里性价比最高的动作——零成本，但直接决定风控画像是否「自相矛盾」。

---

## 为什么时区比 IP 更致命

IP 可以换，时区几乎没人动。绝大多数人的电脑从买回来那天起，时区就写着 `Asia/Shanghai`。

社区逆向披露（2026 年，Claude Code 2.1.91，未经官方证实，但已可自行验证）指出：Claude Code 会读取**系统时区**判断用户是否来自中国大陆时区，并且这个判断**不依赖 IP**——所以你挂什么节点都可能中招。它读的路径至少两条：

1. `Asia/Shanghai` / `Asia/Urumqi` 时区名本身；
2. `ANTHROPIC_BASE_URL` 指向的中转站域名（内置名单比对）。

结论：**出口在美国、时区写着上海 = 典型高危画像。**

---

## 三个方案，按需选

| 方案 | 做法 | 优点 | 代价 |
|---|---|---|---|
| A 基础分流 | 只把 NTP、遥测、认证域名补齐走代理 | 不改系统设置 | 时区仍然露在外面 |
| B 同区替换（推荐） | 时区改成 `Asia/Singapore` 或 `Asia/Taipei` | 仍是 UTC+8，钟表时间分秒不差，日程无感 | 与出口 IP 城市仍不完全一致 |
| C 完全对齐（最彻底） | 时区 = 出口 IP 所在地时区 | 画像最一致，NTP/时区/IP 三者统一 | 看时间要自己换算 |

**新手走 B，进阶走 C。**

---

## Windows

### 1. 看当前时区

```powershell
tzutil /g
Get-TimeZone | Select-Object Id, DisplayName, BaseUtcOffset
```

### 2. 改时区（管理员 PowerShell）

```powershell
# 方案 B：新加坡（UTC+8，与北京时间完全一致）
tzutil /s "Singapore Standard Time"

# 方案 C：跟随出口。美西（洛杉矶）
tzutil /s "Pacific Standard Time"
# 日本
tzutil /s "Tokyo Standard Time"
# 台湾
tzutil /s "Taipei Standard Time"
```

> `tzutil` 用的是 Windows 时区 ID，不是 IANA 名。对照表见文末。

### 3. 关闭「自动设置时区」

设置 → 时间和语言 → 日期和时间 → 关闭 **自动设置时区**（否则联网后又被打回中国时区）。

### 4. 语言与区域

设置 → 时间和语言 → 语言和区域：

- **Windows 显示语言**：可保留简体中文（不影响风控，只影响界面）
- **首选语言顺序**：把 `English (United States)` 加到列表里，并上移到第一位
- **区域格式**：改成 `English (United States)` 或 `Chinese (Singapore)`
- **国家或地区**：改成 `United States` / `Singapore`

> 浏览器上报的 `Accept-Language` 和 `navigator.language` 由这里决定。`zh-CN` + 美国 IP 是仅次于时区的第二大矛盾信号。

### 5. 关掉自动同步

设置 → 时间和语言 → 日期和时间 → 「Internet 时间」→ 更改设置 → 取消勾选「与 Internet 时间服务器同步」，或把服务器指向代理出口所在地区的 NTP。

---

## macOS

```bash
# 查看
sudo systemsetup -gettimezone
# 修改（方案 B）
sudo systemsetup -settimezone Asia/Singapore
# 方案 C
sudo systemsetup -settimezone America/Los_Angeles
# 关闭自动设置时区
sudo systemsetup -setusingnetworktime off
```

图形界面：系统设置 → 通用 → 日期与时间 → 关闭「自动设置时间与时区」。

语言：系统设置 → 通用 → 语言与地区 → 把 English 拖到最上面，区域选 United States。

---

## Linux（VPS / 本地虚拟机）

```bash
timedatectl                      # 查看
sudo timedatectl set-timezone Asia/Singapore
sudo timedatectl set-ntp false   # 关闭自动校时（或用代理侧 NTP）
```

---

## 浏览器侧

| 项 | 建议值 | 检查方式 |
|---|---|---|
| 语言 | `en-US` 优先，可保留 `zh-CN` 作为第二语言 | `navigator.languages` |
| 时区 | 跟系统走（不要用插件单独改，插件改出来的时区常与系统冲突，反而更像伪装） | `Intl.DateTimeFormat().resolvedOptions().timeZone` |
| 地理位置权限 | 一律拒绝 | 站点设置 |
| 指纹插件 | 不要装「随机指纹」类插件；随机化本身就是异常特征 | — |

在 Chrome DevTools Console 里一行验证：

```js
console.log(Intl.DateTimeFormat().resolvedOptions().timeZone, navigator.languages)
```

---

## 时区 ID 对照表

| IANA | Windows ID | UTC |
|---|---|---|
| Asia/Shanghai | China Standard Time | +8 |
| Asia/Singapore | Singapore Standard Time | +8 |
| Asia/Taipei | Taipei Standard Time | +8 |
| Asia/Tokyo | Tokyo Standard Time | +9 |
| Asia/Seoul | Korea Standard Time | +9 |
| America/Los_Angeles | Pacific Standard Time | −8/−7 |
| America/Denver | Mountain Standard Time | −7/−6 |
| America/Chicago | Central Standard Time | −6/−5 |
| America/New_York | Eastern Standard Time | −5/−4 |
| Europe/London | GMT Standard Time | +0/+1 |
| Europe/Berlin | W. Europe Standard Time | +1/+2 |
| Australia/Sydney | AUS Eastern Standard Time | +10/+11 |

> 夏令时会让 UTC 偏移变化。美西在 3 月—11 月是 UTC−7，其余是 UTC−8。选 C 方案时，最好选**不实行夏令时**的地区（如亚利桑那 `America/Phoenix`、夏威夷 `Pacific/Honolulu`、新加坡），避免半年一次的时间跳变被当成异常。

---

## 验收

改完做三件事：

1. 打开 <https://ip.net.coffee/claude/> → 「Claude AI出口IP用户设备信息」卡片 → 时区一行应显示 **时区一致**，不再出现黄标「不推荐使用中国大陆时区」。
2. 同一页面看「语言」是否与 IP 地区匹配。
3. 重启浏览器（时区是进程启动时读取的，改完必须重启，否则页面读到的还是旧值）。

---

## 常见坑

- **改完没重启浏览器** → 页面显示旧时区，以为没生效。
- **只改浏览器不改系统** → Claude Code 读系统时区，仍然中招。
- **用了「时区伪装」插件** → 插件只改 JS 层，NTP 和系统调用仍是真时区，两套信号打架。
- **VPS 里时区没改** → 在 VPS 里跑 Claude Code 时读的是 VPS 时区，默认多为 UTC，虽不是中国大陆时区，但与「美西出口」不一致，建议一并设成出口所在地。
- **NTP 直连** → 系统校时请求从本地出去，返回的时区信息暴露真实位置。分流规则里必须包含 `geosite:category-ntp`（详见 09 分流规则）。
