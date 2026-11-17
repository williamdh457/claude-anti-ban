# 10 · 排障树：症状 → 原因 → 处置

> 用法：先定位症状，再按「先查网络、再查环境、最后查账号」的顺序处理。
> **黄金法则：任何验证弹窗出现时，先别点。先查 IP。点一次，风控记一笔。**

---

## 一、登录 / 访问类

### 1.1 登录转圈、页面白屏

| 可能原因 | 验证 | 处置 |
|---|---|---|
| 出口 IP 被拒 | 检测页 Trust Score / 标记 | 换 IP |
| 分流失效 | 三个出口 IP 不一致 | 补全分流、开 TUN |
| IPv6 偷跑 | 检测页显示 IPv6 | 关 IPv6 |
| Cloudflare 拦截 | 控制台看 403 / challenge | 换 IP + 换 TLS 指纹（`fingerprint: chrome`） |
| 浏览器太旧/魔改 | UA 异常 | 换原版 Chrome |

### 1.2 Cloudflare "Verify you are human" 反复过不去

- 首要原因：IP 信誉差（数据中心共享段、机场出口）；
- 次要：TLS/JA3 指纹不像浏览器（用 curl / python 直连必挂）；
- 处置：换干净 IP → 用真实浏览器 → 清 cookie → 换无痕窗口；
- **不要**连点十几次，越点分数越差。

### 1.3 突然要求邮箱/手机二次验证

- 原因：出口 IP 跳变 / 多设备登录 / 新地区登录；
- 处置：停手 → 修 IP 到与注册时同地区 → 再验证；
- 如果手机号是接码平台的号，这一步基本过不去 → 换号。

### 1.4 弹 "Please verify your identity" / 账号临时禁用

1. **立刻关掉页面**，不要点验证；
2. 打开检测页，把 IP 修到全绿；
3. 清浏览器 cookie，用无痕窗口重登；
4. 仍然不行 → 走申诉（见 1.6）。

### 1.5 Persona 证件核验（类型 B）

- 确认跳转域名是 `withpersona.com` 或官方域名（防钓鱼）；
- 准备**实体**政府证件（护照通过率最高）；
- 光线足、四角入画、不反光；自拍摘口罩墨镜；
- 分流必须覆盖 `withpersona.com`、`frompersona.com`、`maps.googleapis.com`；
- 数字证件、复印件、截图、照片的照片一律拒；
- 18 岁以下不要去验证。

### 1.6 已被封号 → 申诉

```
1. 清痕迹（03）
2. 换出口 IP（01）
3. 时区/语言/IP 三者对齐（04）
4. 检测页全绿 → 截图
5. support.claude.com → "My account has been disabled" / Appeal
   或邮件 support@anthropic.com，主题 "account appeal"
6. 写清：邮箱、用途（个人学习/写作/编程）、无共享无自动化、附全绿截图
7. 等回复，别刷表单
```

> 用脏 IP 申诉 = 主动证明自己是异常用户。

---

## 二、网络 / 泄露类

### 2.1 三个出口 IP 不一致

| 差异形态 | 原因 | 处置 |
|---|---|---|
| 中国 IPv4 是国内 | 分流没生效 / 没开 TUN | 开 TUN，检查规则顺序 |
| 出现 IPv6 | IPv6 未禁用 | 网卡取消 IPv6 + 客户端 `ipv6:false` |
| Cloudflare 与 Claude 出口不同 | 不同域名走了不同节点 | 把 Claude 域名归到同一策略组 |
| 偶尔变一下 | 节点负载均衡 / 多出口 | 固定单节点，关自动切换 |

### 2.2 DNS 泄露

见 `05-dns-leak.md`。速查：

```bash
# 谁在应答
dig +short TXT whoami.ds.akahelp.net
# 系统 DNS
Get-DnsClientServerAddress        # Windows
scutil --dns | grep nameserver    # macOS
resolvectl status                 # Linux
```

处置：客户端 DoH + `fake-ip` + `detour: proxy`；浏览器安全 DNS；系统 DNS 改 1.1.1.1。

### 2.3 WebRTC / UDP 泄露

见 `06-webrtc-leak.md`。速查：

```
chrome://flags/#webrtc-ip-handling-policy → disable_non_proxied_udp
Firefox: media.peerconnection.enabled = false
代理：开 TUN，UDP 走代理或直接丢弃
```

### 2.4 时区不一致

见 `04-timezone-locale.md`。要点：

- 改**系统**时区，不是插件；
- 关「自动设置时区」；
- 改完**重启浏览器**；
- VPS 时区也要改成出口地区。

### 2.5 速度慢 / 频繁超时

| 原因 | 处置 |
|---|---|
| 线路绕路（亚洲→欧洲→北美） | 换机房（洛杉矶/圣何塞） |
| 国际出口拥塞（晚高峰） | 换 CN2 GIA / 换商家 |
| 节点 UDP 被 QoS | 改 TCP-only |
| DNS 解析慢 | 开 fake-ip |
| 单 IP 并发过高 | 并发 ≤5，或分流到多 IP |

---

## 三、客户端类

### 3.1 Claude 桌面端闪退后打不开

```
设置 → 应用 → 安装的应用 → Claude → ··· → 高级选项
→ 先「终止」→ 再「修复」
```

**千万别点「重置」**（会删掉登录状态和全部数据）。

若提示「无法修复此应用，因为它当前正在运行」：

```
Ctrl+Shift+Esc → 任务管理器 → 后台进程 → Claude → 结束任务（可能有多个）
→ 回到设置再点「修复」
```

成功标志：「修复」按钮旁出现 ✔。

### 3.2 桌面端能开但登录转圈 / 对话发不出

- 不是客户端问题，是网络：查 IP 纯净度、分流、TUN；
- 桌面端**不认系统代理**，必须 TUN。

### 3.3 Claude Code 报错

| 报错 | 原因 | 处置 |
|---|---|---|
| 401 / 403 | 分流漏域名、token 失效 | 补规则，重新 OAuth |
| 频繁断连 | 连接复用被关、节点抖动 | 开 keep-alive，固定节点 |
| 429 | 并发过高 / 额度打满 | 并发 ≤5，留 20–30% 余量 |
| `ECONNRESET` | TLS 被干扰 / 协议被识别 | 换 Reality，开 `fingerprint: chrome` |
| OAuth 浏览器打不开 | 默认浏览器是国产套壳 | 换 Chrome/Edge |
| 读取到错误时区 | 系统时区 | 改系统时区（04） |

### 3.4 VSCode 里 Claude 扩展不工作

- 扩展与 CLI 版本不匹配 → 都升级；
- 扩展的 globalStorage 有旧 token → 清掉重登；
- 在虚拟机里跑时，确认扩展装在虚拟机内而不是宿主机。

---

## 四、支付类

见 `08-payment.md`。速查：

| 症状 | 处置 |
|---|---|
| Play 搜不到 Claude | Play 地区 + 节点都改美国，清 Play 缓存 |
| 改地区失败 | 先绑美国账单地址的卡 |
| 卡被拒 | 开通境外支付；换卡；换免税州地址 |
| 订阅成功但仍 Free | 确认 App 内登录的是同一账号 |
| 想退款 | Play 帮助中心 48h 内申请 |

---

## 五、虚拟机类

见 `07-hyperv.md` 第十三节。速查：

| 症状 | 处置 |
|---|---|
| 找不到 Hyper-V 管理器 | 勾选完整 Hyper-V（含管理工具） |
| Boot Failed | 代数选错 / ISO 没挂 |
| 虚拟机没网 | 检查 Default Switch / 重启 vmms |
| 增强会话灰 | 宿主机策略 + 集成服务 |
| 复制粘贴失效 | 用增强会话重连 |
| 分辨率低 | 增强会话 |
| 磁盘膨胀 | 关自动检查点，合并差分盘 |
| 时间漂移 | 开 `vmictimesync` |

---

## 六、判定顺序（任何时候卡住就按这个走）

```
1. 检测页：三个出口 IP 一致吗？        → 否：分流 / TUN / IPv6
2. 检测页：Trust Score ≥ 60？          → 否：换 IP
3. 检测页：DNS 通过吗？                → 否：DoH + detour proxy
4. 检测页：WebRTC 通过吗？             → 否：flag + TUN
5. 检测页：时区一致吗？                → 否：改系统时区
6. 检测页：语言匹配吗？                → 否：改语言列表
7. 以上全绿 → 才怀疑账号本身
8. 账号问题 → 清痕迹 → 换身份要素 → 申诉
```

**90% 的「Claude 出问题」都停在第 1–6 步，不是账号问题。**
