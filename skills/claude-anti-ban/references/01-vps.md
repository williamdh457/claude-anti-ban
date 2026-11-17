# 01 · VPS：选商、开机器、搭节点、接客户端

> 目标：拿到一个**独享、原生、稳定、中国大陆可直连**的出口 IP，并在本地用 TUN 模式把全机流量无遗漏地送出去。
> 为什么不用机场：共享出口 = 连坐。Claude 的封号会顺着 IP 传染，几百人共用一个 IP，你不知道邻居在干什么。

---

## 一、选商

### 1.1 硬指标

| 指标 | 要求 | 怎么验 |
|---|---|---|
| 虚拟化 | KVM（不要 OpenVZ/LXC） | 商品页标注；`systemd-detect-virt` |
| IP 类型 | **原生 IP**，非广播段 | 检测页看 IP 属性 / `whois` 看 netname |
| 地区 | 美国优先（纽约、洛杉矶、达拉斯、硅谷）；日本、新加坡次之 | 商品页可选机房 |
| 线路 | 中国大陆可直连，延迟可接受 | ping.pe / itdog.cn |
| 计费 | 按月，支持支付宝或信用卡 | — |
| 配置 | 1 vCPU / 1 GB / 20 GB 起，跑代理足够 | — |
| 换 IP | 支持开工单免费/低价换 IP | 问客服或看 ToS |

### 1.2 常见方向（自行比价，非推荐）

- **低价按月**：RackNerd、CloudCone、Evoxt、GreenCloud、HostHatch
- **大厂稳定**：Vultr、DigitalOcean、Linode、Hetzner（注意：这些段被机场用烂，纯净度普遍偏低）
- **中国大陆优化线路**：BandwagonHost（CN2 GIA）、DMIT、CloudSilk

> 判断标准只有一个：**这个 IP 段有没有被大量代理/爬虫用过。** 大厂便宜段往往最脏；小众商家的小段反而干净。
> 买之前先想清楚：宁可多花 3 美元买干净段，也别省下钱去跟一万个机场用户共享一个 /24。

### 1.3 别买的东西

- 共享 IP 的虚拟主机 / 合租；
- 「住宅 IP 代理」按流量计费的（可作备选，但延迟和稳定性通常差）；
- 免费试用机（IP 段早已进黑名单）；
- 已经预装好「翻墙面板」的转售机（你不知道上一个用户干了什么）。

---

## 二、开机器（通用流程）

各家面板长得不一样，逻辑一致：

1. 注册 → 邮箱验证 → 充值（支付宝 / 信用卡 / PayPal）；
2. **Deploy / 创建实例**：
   - Location：`New York` / `Los Angeles` / `Dallas`（视频作者选的是美国纽约）
   - Plan：最便宜那档
   - OS：**Ubuntu 22.04 LTS**（或 Debian 12）
3. 确认订单 → 付款 → 等 1–5 分钟开机；
4. 进入控制台 → **Start / 启动** → 记下三样东西：

```
IP 地址：      203.0.113.10
SSH 端口：     22
root 密码：    Xy9#...（面板里可重置）
```

5. 立刻在面板里**重置一次 root 密码**（初始密码常在邮件里明文传输）。

---

## 三、第一件事：测这个 IP 值不值得用

### 3.1 从中国大陆能不能连

- <https://ping.pe/> 输入 IP → 看中国各地节点是否通、丢包率
- <https://www.itdog.cn/ping/> 输入 IP → 看国内三网延迟

判定：

- 全国大面积超时 → **直接开工单换 IP**，别折腾；
- 通但延迟 > 300 ms 且抖动大 → 换机房或换商家；
- 通、延迟 150–250 ms → 可用。

### 3.2 纯净度

在**本地通过这个节点**打开 <https://ip.net.coffee/claude/>，看：

- IP 属性：原生 / 广播 / 住宅 / 机房
- Trust Score
- 是否被标 VPN / Proxy / Tor / Crawler
- 滥用记录

机房 IP 可以接受（作者用机房 IP 稳定一年），但**必须干净、必须独享、必须长期不变**。

### 3.3 换 IP

工单模板：

```
Subject: Request IP replacement

Hello,
The current IP (203.0.113.10) is not reachable from mainland China
and shows high risk on IP reputation checks. Could you please assign
a different IP (ideally a native/clean one in the same location)?
Thank you.
```

多数商家首次免费，之后收 $2–5。

---

## 四、SSH 连接

### Windows（PowerShell / Windows Terminal）

```powershell
ssh root@203.0.113.10
# 首次连接提示指纹，输入 yes
# 粘贴密码时屏幕不显示任何字符（连 * 都没有），这是正常的
```

### macOS / Linux

```bash
ssh -o ServerAliveInterval=30 root@203.0.113.10
```

连上后先做基础加固：

```bash
apt update && apt -y upgrade
# 改 SSH 端口（可选，能少一堆爆破日志）
sed -i 's/^#\?Port .*/Port 2222/' /etc/ssh/sshd_config
systemctl restart ssh

# 时区跟着机房走（重要，别留 UTC）
timedatectl set-timezone America/New_York

# 确认出口
curl -4 https://ipinfo.io
```

---

## 五、搭节点

### 5.1 方案 A：3x-ui 面板（最省事，视频同款路线）

```bash
bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh)
```

安装过程会问：

- 自定义端口（默认随机，记下来）
- 自定义路径（默认随机）
- 管理员用户名 / 密码

装完访问 `http://IP:端口/路径`，登录面板：

1. **入站列表 → 添加入站**
   - 协议：`vless`
   - 端口：`443`
   - 传输：`tcp`
   - 流控：留空
   - 安全：`reality`
   - `dest`：`www.microsoft.com:443`（或 `www.apple.com:443`）
   - `serverNames`：同上域名
   - 生成密钥：点「Get New Cert」旁的钥匙按钮（`x25519`）
   - `shortIds`：随机 8 位十六进制
2. 保存 → 点入站右侧的 **二维码 / 链接** → 复制 `vless://...` 链接

> 面板会给你一条形如
> `vless://uuid@203.0.113.10:443?type=tcp&security=reality&pbk=...&fp=chrome&sni=www.microsoft.com&sid=...&flow=xtls-rprx-vision#us-node`
> 的链接。**这条链接就是你的节点凭据，别外传。**

### 5.2 方案 B：Xray 官方脚本（无面板，纯配置）

```bash
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
xray x25519                      # 生成 private/public key
uuidgen                          # 生成 UUID
```

`/usr/local/etc/xray/config.json`：

```json
{
  "log": { "loglevel": "warning" },
  "inbounds": [
    {
      "port": 443,
      "protocol": "vless",
      "settings": {
        "clients": [{ "id": "YOUR-UUID", "flow": "xtls-rprx-vision" }],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "dest": "www.microsoft.com:443",
          "serverNames": ["www.microsoft.com"],
          "privateKey": "YOUR-PRIVATE-KEY",
          "shortIds": ["0123456789abcdef"]
        }
      }
    }
  ],
  "outbounds": [{ "protocol": "freedom" }]
}
```

```bash
systemctl restart xray && systemctl status xray
```

### 5.3 方案 C：sing-box（一条命令）

```bash
bash <(curl -fsSL https://sing-box.app/deb-install.sh)
```

配置文件 `/etc/sing-box/config.json` 里写 `vless + reality` 入站，然后
`systemctl enable --now sing-box`。

### 5.4 协议选择

| 协议 | 抗识别 | 备注 |
|---|---|---|
| VLESS + Reality | ★★★★★ | 首选，不需要域名和证书 |
| Trojan + TLS | ★★★★ | 需要域名 + 证书（可用 Cloudflare 托管） |
| Hysteria2 | ★★★ | UDP 为主，注意 UDP 泄露与运营商 QoS |
| Shadowsocks | ★★ | 老协议，容易被识别，不建议新搭 |
| VMess | ★ | 别用 |

> 只搭代理**不做**「全局透明转发/内网穿透」之类的额外服务，减少暴露面。

---

## 六、本地客户端：Clash Verge Rev + TUN

### 6.1 安装

从 GitHub Releases 下载对应平台安装包：
<https://github.com/clash-verge-rev/clash-verge-rev/releases>

Windows 装 `.exe`，macOS 装 `.dmg`（首次运行需在「隐私与安全性」里放行）。

### 6.2 把 vless 链接变成订阅

Clash 不直接吃 `vless://`，需要转成订阅文件。两种办法：

**A. 在线转换（最快）**

打开 <https://sub.xeton.dev/>（或自建 subconverter）：

- 目标：`Clash`
- URL：粘贴你的 `vless://...`
- 点 **Convert** → **Download** 得到 `.yaml`

**B. 3x-ui 面板自带订阅**

3x-ui 面板 → 设置 → 订阅 → 开启，然后访问
`http://IP:端口/sub/xxxx` 拿到订阅地址，直接粘进客户端。

### 6.3 导入 Clash Verge

1. 「订阅」→ 新建 → 类型选 **Local**（本地文件）或 **Remote**（订阅 URL）
2. 名称随便填（`us-node`）
3. Local：选择刚下载的 `.yaml`；Remote：粘贴订阅地址
4. 保存 → 右键订阅 → **使用**

### 6.4 关键开关（这一步决定成败）

| 设置 | 值 | 原因 |
|---|---|---|
| **TUN / 虚拟网卡模式** | **开启** | 全机流量无遗漏，包括不认系统代理的程序（Claude 桌面端、Claude Code） |
| 系统代理 | 开启（配合 TUN 更稳） | 浏览器走系统代理 |
| IPv6 | **关闭**（`ipv6: false`） | 防 IPv6 偷跑 |
| DNS | DoH + 走代理 | 防 DNS 泄露 |
| 混合端口 | 默认 7890 | — |
| 规则 | 用 `assets/routing/clash.yaml` 覆盖 | Claude 专用分流 |

配置文件顶部建议：

```yaml
ipv6: false
dns:
  enable: true
  ipv6: false
  enhanced-mode: fake-ip
  nameserver:
    - https://1.1.1.1/dns-query
    - https://8.8.8.8/dns-query
  proxy-server-nameserver:
    - https://1.1.1.1/dns-query
```

### 6.5 验证

```bash
# 出口应该是 VPS 的 IP
curl -4 https://ipinfo.io/ip

# 应该能访问
curl -4 -o /dev/null -s -w "%{http_code} %{time_total}s\n" https://claude.ai/
```

浏览器打开 <https://ip.net.coffee/claude/>，确认：

- 中国出口 IPv4 / Cloudflare 出口 IP / Claude 出口 IP **三者一致**
- 无 IPv6 泄露
- 时区一致

---

## 七、常见问题

| 现象 | 原因 | 处理 |
|---|---|---|
| SSH 连不上 | IP 被墙 / 端口被封 | 面板里换 IP 或换端口；用 IPv6 或控制台 VNC 进去 |
| 面板能开、节点不通 | 防火墙没放行 443 | `ufw allow 443/tcp` / 云厂商安全组放行 |
| 连上但极慢 | 线路绕路 / 国际出口拥塞 | 换机房（洛杉矶→圣何塞）、换商家、上 CN2 |
| 用几天突然全断 | IP 被 GFW 封 | 换 IP；换协议（Reality 换 dest 域名） |
| 检测页显示两个不同 IP | 分流失效或 IPv6 偷跑 | 开 TUN、关 IPv6、补全分流规则 |
| Claude 桌面端不走代理 | 不认系统代理 | **必须开 TUN** |
| 时间显示不对 | VPS 时区是 UTC | `timedatectl set-timezone <出口时区>` |

---

## 八、成本参考

| 项 | 价格 |
|---|---|
| 入门 VPS（1C1G，美国） | $10–20 / 年（低价商家）～ $6 / 月（大厂） |
| 干净原生 IP 段 | $15–30 / 年 |
| 换 IP | $0–5 / 次 |
| Claude Pro | $20 / 月 |
| Claude Max | $100 / 月 起 |

**一年总成本 ≈ 一台 VPS + 订阅费。** 比反复被封号重注册便宜得多。
