# 09 · Claude 专用分流规则（一个域名都不能漏）

> Claude Code 运行时不止访问 `claude.ai`。它还会碰 CDN、OAuth 认证、错误监控、AB 测试、客服 widget、NTP 校时。**漏一个域名 = 一次「一半走代理一半直连」的地域矛盾。**
> 现成规则文件在 `assets/routing/`，本文讲原理、讲怎么接、讲怎么验。

---

## 一、为什么必须单独分流

| 做法 | 问题 |
|---|---|
| 全局代理 | 能用，但慢；且部分国内服务会异常 |
| 智能分流（`geosite:geolocation-!cn`） | Claude 的请求可能被分到不同节点，甚至命中直连规则 |
| 只写 `claude.ai` + `api.anthropic.com` | 漏掉 CDN/认证/监控/NTP，仍然泄露 |
| **Claude 专用规则 + 最高优先级 + IP 兜底** | ✅ 正确做法 |

---

## 二、完整域名表

### 核心（缺一不可）

| 域名 | 用途 |
|---|---|
| `anthropic.com` | Anthropic 主站 |
| `claude.ai` | Claude 网页版 |
| `claude.com` | 备用域名 |
| `clau.de` | 短域名（重定向） |
| `claudemcpclient.com` | MCP 客户端通信 |
| `claudemcpcontent.com` | MCP 内容分发 |
| `claudeusercontent.com` | 用户内容 / 附件 |

### CDN / 基础设施

| 域名 | 用途 |
|---|---|
| `cdn.anthropic.com` | CDN |
| `anthropic.com.cdn.cloudflare.net` | Cloudflare CDN 节点 |
| `servd-anthropic-website.b-cdn.net` | BunnyCDN 静态资源 |

### 认证 / 内容

| 域名 | 用途 |
|---|---|
| `anthropic.auth0.com` | OAuth 登录 |
| `anthropic-com.ghost.io` | 博客 / CMS |
| `console.anthropic.com` | API 控制台 |
| `workbench.anthropic.com` | Workbench |
| `mcp.anthropic.com` | MCP 服务 |
| `support.claude.com` | 支持中心（申诉也在这） |

### KYC（遇到证件核验必加）

| 域名 | 用途 |
|---|---|
| `withpersona.com` | Persona 证件核验 |
| `frompersona.com` | KYC 邮件通知 |
| `maps.googleapis.com` | 地图 / 位置解析 |

> KYC 页面如果有一半请求直连，会暴露真实 IP——**核验过程中暴露比不核验更糟**。

### 监控 / 遥测（最容易被忽略）

| 域名 / 关键词 | 用途 |
|---|---|
| `sentry.io` | 错误上报 |
| `statsigapi.net` | 功能开关 / AB 测试 |
| `browser-intake-us5-datadoghq.com` | Datadog RUM（**精确域名，不是 datadoghq.com 的子域**） |
| 关键词 `datadog` | APM 兜底（区域端点会变） |
| 关键词 `sift` | 反欺诈检测 |

> `browser-intake-us5-datadoghq.com` 中间是**连字符**不是点，`DOMAIN-SUFFIX,datadoghq.com` 抓不到它，必须单独一条精确匹配。

### 客服 / 统计

| 域名 | 用途 |
|---|---|
| `intercom.io` / `intercomcdn.com` | 在线客服 |
| `cdn.usefathom.com` | 访问统计 |

> 纯 API 用户可以把这三条改成 `REJECT`；只要你会打开网页版、支付页、博客，就走代理保持出口一致。

### IP / ASN 兜底（最后一道防线）

| 规则 | 说明 |
|---|---|
| `160.79.104.0/21` | Anthropic 自有 IPv4 段（2048 个 IP） |
| `2607:6bc0::/32` | Anthropic IPv6 段 |
| `IP-ASN,399358` | Anthropic PBC 的 ASN |

用途：当域名规则因为 DoH 加密、ECH/ESNI 隐藏 SNI、或客户端用了未知新域名而失效时，IP 规则兜底。

写法要点：

- `IP-CIDR` 加 `no-resolve`，避免每个域名都反查 IP（降 CPU、降首包延迟）；
- IP 规则放在域名规则**之后**；
- `IP-ASN` 需要客户端内置 GeoIP/ASN 库，不支持就只用前两条。

---

## 三、NTP：最隐蔽的一条

Claude Code 会通过 **UDP** 访问 NTP 服务器判断时区。NTP 直连 = 真实时区暴露。

```
GEOSITE,category-ntp,PROXY
```

同时注意：

- NTP 走 UDP，很多客户端默认不代理 UDP，要显式开启；
- 系统层建议关闭自动校时，或把 NTP 指向出口地区的服务器；
- 配合禁用 IPv6，彻底消除时区泄露。

---

## 四、四种引擎写法

现成文件：

| 引擎 | 文件 |
|---|---|
| Clash / Mihomo / Stash | `assets/routing/clash.yaml` |
| sing-box | `assets/routing/singbox-rule-set.json` |
| Surge / Loon / Quantumult X | `assets/routing/surge.conf` |
| 纯域名列表（任意工具） | `assets/routing/domain-list.txt` |

### Clash 接法

把 `clash.yaml` 里的 `rules:` 内容**插到你订阅规则的 `rules:` 最前面**，或写进 Verge 的「Merge / 全局扩展配置」：

```yaml
# Clash Verge → 订阅 → 右键 → 编辑 → Merge
prepend-rules:
  - DOMAIN-SUFFIX,anthropic.com,PROXY
  - DOMAIN-SUFFIX,claude.ai,PROXY
  # ...（其余照抄）
```

### sing-box 接法

```json
{
  "route": {
    "rule_set": [
      { "type": "local", "tag": "claude", "path": "./claude-rule-set.json" }
    ],
    "rules": [
      { "rule_set": "claude", "outbound": "proxy" }
    ],
    "final": "proxy"
  }
}
```

### Surge 接法

把 `surge.conf` 内容粘到 `[Rule]` 段最前面，`POLICY` 换成你的策略组名。

### 通用要点

1. 规则**顺序**：Claude 专用 → 其他自定义 → geosite/geoip 通配；
2. `final` / 兜底策略指向代理，而不是 DIRECT；
3. 改完**重启客户端**，并用检测页验证；
4. 订阅更新会覆盖规则 → 用 Merge / 覆写文件，别直接改订阅缓存。

---

## 五、验证

```bash
# 1) 出口一致性
curl -4 https://ipinfo.io/ip
curl -4 https://www.cloudflare.com/cdn-cgi/trace | grep ^ip=

# 2) 关键域名是否走代理（看是否拿到 Anthropic 的 IP 段）
dig +short claude.ai
dig +short api.anthropic.com

# 3) 延迟
curl -o /dev/null -s -w "%{http_code} %{time_total}s\n" https://claude.ai/
curl -o /dev/null -s -w "%{http_code} %{time_total}s\n" https://api.anthropic.com/
```

浏览器侧：<https://ip.net.coffee/claude/> → 三个出口 IP 一致 + DNS/WebRTC 通过。

---

## 六、常见错误

| 错误 | 后果 | 修法 |
|---|---|---|
| 只写 `claude.ai` | CDN/监控直连，出口不一致 | 用完整清单 |
| 规则放在 geosite 之后 | 被通配规则抢先匹配 | 移到最前面 |
| 用「智能分流」模式 | 节点随机，IP 跳变 | 关掉，改规则模式 |
| 忘记 NTP | 时区泄露 | 加 `category-ntp` |
| 忘记 IP 兜底 | 新域名上线即漏 | 加 `160.79.104.0/21` |
| 订阅一更新就失效 | 规则被覆盖 | 用 Merge/覆写 |
| `IP-CIDR` 没加 `no-resolve` | 延迟升高 | 补上 |
| KYC 时漏 `withpersona.com` | 核验过程暴露真实 IP | 补上 |
