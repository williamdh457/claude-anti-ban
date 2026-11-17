# 05 · DNS 泄露：原理、检测、三层修法

> 一句话：**你的连接走了代理，但「问路」这件事还是本地运营商在替你问——风控看到的就是「IP 在纽约，DNS 在上海」。**

---

## 一、泄露是怎么发生的

一次访问 Claude 的过程：

```
浏览器 ──① 解析 claude.ai ──→ DNS 服务器（谁？）
       ──② 建立 TLS 连接 ──→ 代理节点 ──→ claude.ai
```

如果 ① 走的是本地运营商 DNS（`192.168.1.1` → 电信/联通 DNS），而 ② 走的是美国节点，那么：

- Anthropic / Cloudflare 看到：连接来自美国 IP；
- 同时你的 DNS 查询暴露给本地运营商，且某些场景下（ECS、EDNS Client Subnet）会把你的**真实网段**带给权威服务器。

两者不一致 = 地域矛盾 = 风控加权。

更隐蔽的三种情况：

1. **DoH 没走代理**：浏览器自己直连 `1.1.1.1` 做 DoH，虽然内容加密了，但**目的地**仍是 Cloudflare 的本地就近节点，Cloudflare 依然知道你在中国。
2. **IPv6 的 AAAA 查询直连**：IPv4 走了代理，AAAA 记录从本地出去，解析结果与 IPv4 不一致 → 地区漂移。
3. **代理客户端的 DNS 分流**：`dns.nameserver` 是本地 DNS、`fallback` 才是远端，命中顺序不对就泄露。

---

## 二、检测

### 2.1 权威检测（推荐）

<https://ip.net.coffee/dns/>

原理：自建权威 DNS，让你解析一个唯一子域名，看**最终是哪台递归服务器来问的**。

- 显示「通过」且 DNS 出口 IP = 你的代理出口 IP → 正常
- 显示中国大陆 IP / 与出口不一致 → 泄露

### 2.2 交叉验证

- <https://www.dnsleaktest.com/>（Extended test）
- <https://browserleaks.com/dns>
- 命令行：

```bash
# 看系统当前用的 DNS
# Windows
Get-DnsClientServerAddress | Where-Object {$_.ServerAddresses}
# macOS
scutil --dns | grep nameserver
# Linux
resolvectl status | grep -A2 "DNS Servers"
```

### 2.3 用 dig 看「谁在答」

```bash
dig +short TXT whoami.ds.akahelp.net
# 返回里会有你的出口 IP —— 与代理出口一致才算干净
```

---

## 三、三层修法（三层都要做）

### 第 1 层：代理客户端（最关键）

**Clash / Mihomo**

```yaml
dns:
  enable: true
  ipv6: false
  enhanced-mode: fake-ip
  fake-ip-range: 198.18.0.1/16
  default-nameserver:
    - 223.5.5.5          # 只用于解析 DoH 域名本身
  nameserver:
    - https://1.1.1.1/dns-query
    - https://8.8.8.8/dns-query
  proxy-server-nameserver:
    - https://1.1.1.1/dns-query
  nameserver-policy:
    "geosite:cn": "223.5.5.5"
    "+.anthropic.com": "https://1.1.1.1/dns-query"
    "+.claude.ai": "https://1.1.1.1/dns-query"
```

要点：

- `enhanced-mode: fake-ip` — 让域名解析**不真正发生**，等连接建立时由代理端解析，从根上消灭本地 DNS 泄露；
- `nameserver` 全部是 DoH，且这些 DoH 请求由代理发出；
- Claude 相关域名单独指定远端 DoH。

**sing-box**

```json
{
  "dns": {
    "servers": [
      { "tag": "remote", "address": "https://1.1.1.1/dns-query", "detour": "proxy" },
      { "tag": "local", "address": "223.5.5.5", "detour": "direct" }
    ],
    "rules": [
      { "domain_suffix": ["anthropic.com", "claude.ai"], "server": "remote" }
    ],
    "final": "remote",
    "strategy": "ipv4_only"
  }
}
```

**必须显式写 `"detour": "proxy"`**，否则 DoH 请求可能走 direct。

### 第 2 层：浏览器

- Chrome / Edge：设置 → 隐私和安全 → 安全 → **使用安全 DNS** → 选 `Cloudflare (1.1.1.1)`，或自定义 `https://dns.cloudflare.com/dns-query`
  - 如果代理已开 TUN，浏览器 DoH 会被 TUN 接管，安全；
  - 如果没开 TUN，浏览器 DoH 会直连 → 反而泄露「你在用 Cloudflare 本地节点」。**所以 TUN 是前提。**
- Firefox：`about:config` → `network.trr.mode = 3`（只用 TRR）、`network.trr.uri = https://cloudflare-dns.com/dns-query`
- Safari：跟随系统

### 第 3 层：系统

```powershell
# Windows：网卡 DNS 改成公共 DNS（避免运营商 DNS 参与）
Set-DnsClientServerAddress -InterfaceAlias "Wi-Fi" -ServerAddresses 1.1.1.1,8.8.8.8
```

```bash
# macOS
networksetup -setdnsservers "Wi-Fi" 1.1.1.1 8.8.8.8
# Linux（systemd-resolved）
sudo resolvectl dns wlan0 1.1.1.1 8.8.8.8
```

改完清缓存：

```bash
ipconfig /flushdns                                        # Windows
sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder   # macOS
sudo resolvectl flush-caches                              # Linux
```

### 附加：把 NTP 也纳入代理

系统校时会泄露真实时区。分流规则里加：

```
DOMAIN-SUFFIX,ntp.org,PROXY
GEOSITE,category-ntp,PROXY
```

并在系统里关闭自动校时，或把 NTP 服务器指向出口地区的地址。

---

## 四、验收

```bash
bash scripts/check_env.sh --dns
```

或在检测页看：

- DNS 泄露：**通过**
- DNS 出口 IP = 代理出口 IP
- 三个出口 IP 一致

---

## 五、常见坑

| 现象 | 原因 | 修法 |
|---|---|---|
| 检测页 DNS 通过，但 dnsleaktest 显示中国 | 部分查询仍走本地（IPv6 或 fallback） | 关 IPv6，`final` 指向 remote |
| 开了 DoH 反而更慢 | DoH 走了直连，绕路 | 确保 TUN 开启 / `detour: proxy` |
| 换节点后 DNS 又泄露 | 配置文件被订阅覆盖 | 把 DNS 段写进「合并配置 / Merge」，别只改订阅 |
| 公司网络下怎么都不行 | 网关强制劫持 53 端口 | 用 DoH（443）绕过；或换网络 |
| 用 fake-ip 后某些 App 报错 | App 不认 198.18.x.x | 给该域名加 `fake-ip-filter` |
