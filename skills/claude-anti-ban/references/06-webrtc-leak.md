# 06 · WebRTC / UDP 泄露：原理、检测、关闭

> 一句话：**WebRTC 会绕过你的代理，直接向 STUN 服务器问「我的公网 IP 是多少」，然后把答案交给网页。**
> 结果：网页里的 JS 拿到了你的真实 IP，而 HTTP 请求是从代理出去的——两个 IP，一个身份。

---

## 一、原理

WebRTC 为了打洞（NAT 穿透），需要知道自己的公网地址，于是：

```
浏览器 ──UDP/STUN──→ stun.l.google.com:19302
        ←── 你的公网 IP:端口 ──
```

这条 UDP 请求**不走 HTTP 代理**（HTTP 代理只处理 TCP）。所以：

- 你的网页请求：走代理 → 美国 IP
- 你的 WebRTC STUN：走本地 UDP → 中国 IP

风控脚本只要跑一行 `RTCPeerConnection` 就能拿到这个矛盾。更糟的是，某些实现还会泄露**内网 IP**（`192.168.x.x`），直接暴露你的网络结构。

### 三种泄露

| 类型 | 泄露内容 |
|---|---|
| 公网 IP 泄露 | 真实出口 IP（最致命） |
| 内网 IP 泄露 | `192.168.x.x` / `10.x.x.x`（暴露网络环境） |
| mDNS 泄露 | `.local` 主机名（暴露设备名） |

---

## 二、检测

### 2.1 专用页面（推荐）

<https://ip.net.coffee/webrtc/>

看「UDP 出口 IP」是否等于你的代理出口 IP。

### 2.2 交叉验证

- <https://browserleaks.com/webrtc>
- <https://ipleak.net/>

### 2.3 手动一行

浏览器 Console：

```js
const pc = new RTCPeerConnection({iceServers:[{urls:'stun:stun.l.google.com:19302'}]});
pc.createDataChannel('');
pc.onicecandidate = e => e.candidate && console.log(e.candidate.candidate);
pc.createOffer().then(o => pc.setLocalDescription(o));
```

如果打印出来的 IP 不是你的代理出口 IP → 泄露。

---

## 三、关闭方法

### 3.1 Chrome / Edge（推荐做法）

**方法 A：flag（个人使用）**

```
chrome://flags/#webrtc-ip-handling-policy
→ 选 "Disable non-proxied UDP"
→ 重启浏览器
```

Edge 同理：`edge://flags/#webrtc-ip-handling-policy`

**方法 B：企业策略（更彻底，重启不丢）**

Windows 注册表：

```
HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Google\Chrome
  WebRtcIPHandlingPolicy = disable_non_proxied_udp   (REG_SZ)
  WebRtcLocalIpsAllowedUrls = []                      (可选)
```

macOS：

```bash
sudo defaults write com.google.Chrome WebRtcIPHandlingPolicy -string disable_non_proxied_udp
```

`disable_non_proxied_udp` 的含义：**只允许通过代理的 UDP**，非代理 UDP 一律禁用 → WebRTC 拿不到真实 IP。

### 3.2 Firefox

`about:config`：

```
media.peerconnection.enabled = false          # 直接禁用 WebRTC
media.peerconnection.ice.default_address_only = true
media.peerconnection.ice.no_host = true
```

> 禁用 WebRTC 会影响网页版会议/语音。用 Claude 网页版不需要 WebRTC，可以放心关。

### 3.3 Safari

Safari 没有细粒度开关，靠两件事：

- 系统级：iCloud+ 的「隐藏 IP 地址」（只对 Safari 私有中继生效，不覆盖代理场景）
- 真正的解法：**代理开 TUN 模式**，让 UDP 也被接管

### 3.4 代理端（最根本的一层）

| 客户端 | 设置 |
|---|---|
| Clash / Mihomo | TUN 开启（`tun.enable: true`，`stack: system/gvisor`），`udp: true` 在节点上；若不想代理 UDP，把节点 `udp` 设为 `false` 并确保规则不回落直连 |
| sing-box | `"inbounds": [{"type":"tun", "stack":"gvisor", ...}]`，路由里 `"network": ["tcp"]` 可强制只走 TCP |
| 通用 | 关掉「UDP 直通 / UDP 转发」，让所有 UDP 要么走代理、要么被丢弃（丢弃比直连安全） |

**推荐组合：TUN 接管全部流量 + 浏览器 `disable_non_proxied_udp` + 节点开启 UDP。** 这样 WebRTC 的 STUN 也会从代理出口出去，UDP 出口 IP 与 HTTP 出口一致。

### 3.5 强制 TCP（可选，最保守）

如果不需要 UDP 类应用（游戏、语音），可以让代理只走 TCP：

```yaml
# Clash 节点层
- name: us-node
  type: vless
  ...
  udp: false
```

```json
// sing-box 出站
{ "type": "vless", "tag": "proxy", "server": "...", "network": "tcp" }
```

代价：QUIC/HTTP3 会回落 TCP，速度略降；好处：UDP 泄露面直接归零。

---

## 四、验收

| 检查 | 通过标准 |
|---|---|
| <https://ip.net.coffee/webrtc/> | UDP 出口 IP = 代理出口 IP |
| <https://browserleaks.com/webrtc> | 只显示代理 IP，无内网 IP、无 mDNS |
| 检测页「WebRTC UDP 泄露」 | 状态正常 |
| 三个出口 IP | 完全一致 |

---

## 五、常见坑

| 现象 | 原因 | 修法 |
|---|---|---|
| flag 改了没效果 | 浏览器没完全退出（后台进程还在） | 任务管理器结束所有 chrome 进程再开 |
| 每次更新后又泄露 | flag 被重置 | 改用注册表策略 |
| 只有 Edge 泄露 | 只改了 Chrome | 两个浏览器分别设 |
| 关了 WebRTC 还是显示真实 IP | 那是 IPv6 泄露，不是 WebRTC | 去关 IPv6 |
| 虚拟机里检测异常 | 虚拟机网卡是 NAT，UDP 行为不同 | 虚拟机里也要开 TUN，别只依赖宿主 |
| UDP 出口是节点 IP 但延迟高 | UDP QoS 被运营商限速 | 改 TCP-only 模式 |
