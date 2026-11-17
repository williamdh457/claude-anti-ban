# 07 · Hyper-V：干净的 Claude 专用虚拟机

> 为什么值得单独做一台虚拟机：Claude Code 有你的文件系统权限，能读环境变量、时区、配置、装了什么软件。宿主机上装过国产工具、接过国产模型中转、登过别的号——这些都是污染源。
> 视频作者的做法：Hyper-V 里一台虚拟机，**只装浏览器 + VSCode + Claude 桌面端**，时区美国、语言英语，一号一机，长期不动。

---

## 一、为什么选 Hyper-V

| | VMware Workstation | VirtualBox | **Hyper-V** |
|---|---|---|---|
| 成本 | 高（约 $149） | 免费开源 | **低**（只需 Windows 专业版） |
| 稳定性 | 中 | 低 | **最高**（内嵌于 Windows） |
| 性能 | 中 | 最低 | **最高**（启动快、占用小） |
| GPU 虚拟化 | 支持 | 弱 | 支持 |
| 与 Windows 集成 | 一般 | 一般 | **最好**（增强会话、剪贴板、驱动器重定向） |

结论：Windows 上做「长期挂着的干净环境」，Hyper-V 是性价比最高的选择。

---

## 二、前置条件

| 项 | 要求 | 检查方法 |
|---|---|---|
| Windows 版本 | **专业版 / 企业版 / 教育版** | 设置 → 系统 → 系统信息 |
| CPU 虚拟化 | BIOS 中已开启 VT-x / AMD-V | 任务管理器 → 性能 → CPU → 「虚拟化：已启用」 |
| 内存 | ≥ 16 GB（给虚拟机 4–8 GB） | 任务管理器 |
| 磁盘 | ≥ 100 GB 空闲 | — |
| 其他虚拟化软件 | 关掉 VMware/VirtualBox/WSL2 的冲突（可选） | — |

> **家庭版**怎么办：两条路
> 1. 升级到专业版（设置 → 系统 → 激活 → 更改产品密钥，输入专业版密钥，重启）；
> 2. 用 DISM 从专业版 ISO 里强装 Hyper-V 包（社区脚本做法，能用但不受官方支持，更新后可能失效）。**推荐走 1。**

---

## 三、步骤 1：拿到纯净 Windows 10 ISO

不要用「某某之家」「系统之家」的修改版镜像——预装软件、改过的注册表、捆绑的驱动，全是污染。

1. 打开 <https://www.microsoft.com/software-download/windows10>
2. 点 **立即下载工具**（Media Creation Tool）
3. 运行 → 接受协议
4. **重点**：选择 **「为另一台电脑创建安装介质（U 盘、DVD 或 ISO 文件）」**（不是「立即升级这台电脑」）
5. 语言 / 版本 / 体系结构：按需（建议 64 位，中文或英文都行）
6. 选择介质：**ISO 文件**
7. 选保存位置（如 `D:\ISO\Win10_22H2.iso`）
8. 等进度条走完 → 得到官方原版 ISO

> 想要英文系统（更贴近美国用户画像）：在第 5 步语言选 `English (United States)`。
> 也可以用 <https://www.microsoft.com/software-download/windows11> 拿 Win11 ISO，但 Win11 在 Hyper-V 里需要 Gen2 + TPM，麻烦一些（见第八节）。

---

## 四、步骤 2：确认 / 升级 Windows 版本

```powershell
# 一行看版本
(Get-ComputerInfo).WindowsProductName
```

或：设置 → 系统 → 系统信息 → 看「Windows 规格」。

- 显示 **专业版 / 企业版 / 教育版** → 直接进下一步
- 显示 **家庭版** → 设置 → 系统 → 激活 → **更改产品密钥** → 输入专业版密钥 → 下一步 → 自动重启

> 密钥来源自行解决（正规渠道购买最省心）。升级过程不会重装系统，文件和软件都保留。

---

## 五、步骤 3：开启 Hyper-V

### 方法 A：图形界面（与视频一致）

1. 开始菜单搜索 **「启用或关闭 Windows 功能」**
2. 勾选 **Hyper-V**（会连带勾选「Hyper-V 管理工具」和「Hyper-V 平台」）
3. 确定 → 等进度条 → **立即重新启动**

### 方法 B：PowerShell（管理员）

```powershell
Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All -All -NoRestart
Restart-Computer
```

### 方法 C：DISM

```powershell
DISM /Online /Enable-Feature /All /FeatureName:Microsoft-Hyper-V
```

### 验证

```powershell
Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All | Select State
Get-Service vmms, vmcompute | Select Name, Status
```

两个服务都是 `Running` 才算成功。

> 如果开了 Hyper-V 后 VMware/VirtualBox 变慢或报错，是两者抢 VT-x 导致的。日常用 Hyper-V 就把另一家的虚拟化引擎关掉，反之亦然。

---

## 六、步骤 4：创建虚拟机

### 方法 A：图形界面（照视频走）

1. 开始菜单搜索 **Hyper-V 管理器** → 打开
2. 右侧 **新建 → 虚拟机** → 下一页
3. **名称**：`ClaudeBox`；**位置**：改到非系统盘（如 `D:\VMs`）→ 下一页
4. **代数**：**第一代**（更稳；装 Win11 才需要第二代）→ 下一页
5. **内存**：`6144` MB，**取消**「使用动态内存」（固定内存更稳，不会因宿主机压力卡顿）→ 下一页
6. **网络**：`Default Switch`（自带 NAT，开箱能上网）→ 下一页
7. **虚拟硬盘**：`80` GB，位置默认 → 下一页
8. **安装选项**：**从可启动的 CD/DVD-ROM 安装操作系统** → 映像文件选第 3 步的 ISO → 下一页 → 完成
9. 右键虚拟机 → **连接** → 点 **启动**

### 方法 B：PowerShell（一条命令建完）

```powershell
# 已由 scripts/hyperv_setup.ps1 封装，也可手工执行
New-VM -Name "ClaudeBox" `
       -MemoryStartupBytes 6GB `
       -Generation 1 `
       -NewVHDPath "D:\VMs\ClaudeBox\ClaudeBox.vhdx" `
       -NewVHDSizeBytes 80GB `
       -SwitchName "Default Switch"

Set-VMDvdDrive -VMName "ClaudeBox" -Path "D:\ISO\Win10_22H2.iso"
Start-VM -Name "ClaudeBox"
vmconnect.exe localhost "ClaudeBox"
```

---

## 七、步骤 5：安装系统

在 vmconnect 窗口里：

1. 「Press any key to boot from CD or DVD」→ 按任意键
2. 语言 / 时间格式 / 键盘 → 下一步 → **现在安装**
3. **我没有产品密钥**（装完再激活，或一直用未激活状态——不影响使用）
4. 版本选 **Windows 10 专业版** → 下一步 → 接受条款
5. **自定义：仅安装 Windows（高级）** → 选那块 80 GB 未分配空间 → 下一步
6. 等安装 + 自动重启（重启后不要再按键从 CD 启动）
7. 区域设置：**United States**（重要！这决定系统区域）
8. 键盘：`US`
9. 第二种键盘布局：跳过
10. 网络：可以选「我没有 Internet 连接」→「继续执行受限设置」，建本地账户（**别用微软账户登录**，少一层身份绑定）
11. 用户名随意（建议英文名），密码可留空
12. 隐私设置：全部关闭
13. 进入桌面 → 「有限的体验」提示可以直接忽略

---

## 八、步骤 6：装完后的「干净基线」配置（这一步才决定防封效果）

按顺序做：

### 1. 时区与语言

```powershell
# 管理员 PowerShell
tzutil /s "Eastern Standard Time"          # 跟随美东出口
# 或 tzutil /s "Pacific Standard Time"
Set-WinUILanguageOverride -Language en-US
Set-WinUserLanguageList -LanguageList en-US -Force
Set-Culture en-US
```

设置 → 时间和语言 → 关闭「自动设置时区」。

### 2. 关 IPv6

```powershell
Disable-NetAdapterBinding -Name "Ethernet" -ComponentID ms_tcpip6
```

（Hyper-V 虚拟网卡名一般是 `Ethernet`，用 `Get-NetAdapter` 确认。）

### 3. 装代理客户端 + 开 TUN

- 装 Clash Verge Rev / sing-box
- 导入节点（见 `01-vps.md`）
- **开启 TUN / 虚拟网卡模式**（虚拟机内也必须开，别指望宿主机的 TUN 覆盖到虚拟机）
- 导入 `assets/routing/clash.yaml` 分流规则

### 4. 装软件（只装这三个）

- 浏览器（Chrome / Edge）
- VSCode
- Claude 桌面客户端

**不要装**：国产输入法云同步、国产安全软件、国产浏览器、任何「AI 加速器」、任何接国产模型的插件。

> 输入法：用系统自带微软拼音（关闭云候选），或装 RIME 这类纯本地输入法。

### 5. 浏览器配置

- 语言列表只留 `en-US`
- 安全 DNS → Cloudflare
- `chrome://flags/#webrtc-ip-handling-policy` → `disable_non_proxied_udp`
- 地理位置权限 → 拒绝
- 不装指纹插件

### 6. 打检查点（快照）

Hyper-V 管理器 → 右键虚拟机 → **检查点** → 命名为 `clean-baseline`。

以后环境脏了、装错东西了、被封了，直接 **还原到 clean-baseline**，30 秒回到干净状态。这是 Hyper-V 相对其他方案最大的优势。

---

## 九、增强会话模式（体验提升关键）

默认的 vmconnect 只有 1024×768、不能复制粘贴、不能传文件。开启增强会话后可以：自适应分辨率、双向剪贴板、拖拽文件、驱动器重定向、音频。

### 宿主机侧

1. Hyper-V 管理器 → 右侧 **Hyper-V 设置**
2. 「服务器」→ **增强会话模式策略** → 勾选「允许增强会话模式」
3. 「用户」→ **增强会话模式** → 勾选「允许增强会话模式」

### 虚拟机侧

1. 虚拟机设置 → **管理** → **集成服务** → 全部勾选（尤其「来宾服务」）
2. 虚拟机内确认服务在跑：

```powershell
Get-Service vmicvss, vmictimesync, vmicheartbeat, vmicshutdown, vmicguestinterface
```

### 使用

vmconnect 连接时会弹「显示配置」→ 选分辨率 → 连接。之后剪贴板和拖拽就通了。

---

## 十、文件互传

| 方式 | 做法 | 适用 |
|---|---|---|
| 增强会话剪贴板 | 直接 Ctrl+C / Ctrl+V | 小文本、少量文件 |
| 增强会话驱动器 | 连接时「本地资源」→ 更多 → 驱动器 → 勾选 | 传 ISO、安装包 |
| PowerShell Direct | 宿主机执行 `Copy-VMFile -VMName ClaudeBox -SourcePath x -DestinationPath y -CreateFullPath -FileSource Host` | 脚本化 |
| 共享文件夹 | 虚拟机内 `net use Z: \\<宿主机IP>\share` | 长期共享（注意别把敏感目录共享进去） |

> **纪律**：不要把宿主机整盘挂进虚拟机。只共享单个文件夹，且里面不放账号相关的东西。

---

## 十一、性能调优

| 项 | 建议 |
|---|---|
| 内存 | 固定 6 GB（不要动态内存，避免抖动） |
| vCPU | 2–4 个（不要超过物理核心数的一半） |
| 硬盘 | 固定大小 VHDX 比动态扩展快；至少 80 GB |
| 检查点 | **关闭自动检查点**（否则差分盘无限膨胀）<br>`Set-VM -Name ClaudeBox -AutomaticCheckpointsEnabled $false` |
| 显卡 | 不装 3D 加速也行；但**必须装集成服务**，否则 WebGL 显示 `SwiftShader`（异常指纹） |
| 时间同步 | 集成服务里的「时间同步」保持开启，否则虚拟机时间会漂 |
| 休眠 | 虚拟机内关闭休眠，减少磁盘写入 |

---

## 十二、Windows 11 的额外要求

Win11 在 Hyper-V 里需要：

- **第二代**虚拟机（UEFI）
- **TPM 2.0**：`Set-VMKeyProtector -VMName ClaudeBox -NewLocalKeyProtector` + `Enable-VMTPM -VMName ClaudeBox`
- **安全启动**：`Set-VMFirmware -VMName ClaudeBox -EnableSecureBoot On`
- CPU 至少 2 vCPU、内存 ≥ 4 GB、磁盘 ≥ 64 GB

```powershell
Set-VM -Name ClaudeBox -Generation 2
Set-VMProcessor -VMName ClaudeBox -Count 2
Set-VMKeyProtector -VMName ClaudeBox -NewLocalKeyProtector
Enable-VMTPM -VMName ClaudeBox
Set-VMFirmware -VMName ClaudeBox -EnableSecureBoot On
```

> 只是用来跑 Claude，**装 Win10 更省事**。Win11 的 TPM/安全启动折腾半天，收益为零。

---

## 十三、常见问题

| 现象 | 原因 | 处理 |
|---|---|---|
| 开启 Hyper-V 后找不到 Hyper-V 管理器 | 只勾了「平台」没勾「管理工具」 | 重新勾选完整 Hyper-V |
| 虚拟机启动报 `Boot Failed. EFI SCSI Device` | 代数选错（Gen2 但 ISO 不支持 UEFI）或 ISO 没挂上 | 改第一代，或检查 DVD 驱动器路径 |
| 虚拟机没网 | Default Switch 的 NAT 异常 | `Get-VMSwitch`；重启 `nvspwmi`/`vmms`；或新建 Internal + NAT |
| 增强会话是灰的 | 宿主机策略没开 / 虚拟机没装集成服务 | 见第九节 |
| 复制粘贴不通 | 用的是「基本会话」 | 断开重连，选增强会话 |
| 分辨率只有 1024×768 | 没开增强会话 | 同上 |
| 虚拟机时间不对 | 集成服务时间同步被关 | 打开 `vmictimesync` |
| 磁盘越来越大 | 自动检查点 + 动态扩展 | 关自动检查点，合并差分盘 |
| 装完系统进不去桌面 | 安装时选了「升级」而非「自定义」 | 重装，选自定义 |
| 宿主机蓝屏 / 卡死 | 内存给太多 / 与 VMware 冲突 | 降内存，关掉另一家虚拟化 |

---

## 十四、与防封的关系（别把它当纯技术活）

虚拟机真正的价值是**可控的干净基线**：

1. **一机一号**：这台 VM 只登一个 Claude 账号，不登第二个；
2. **可回滚**：环境被污染 → 还原检查点，不用重装系统；
3. **可复制**：想开第二台（养小号）→ 导出/复制 VHDX，改个名字和 MAC 就是新机器；
4. **隔离**：宿主机上折腾什么都不影响它；
5. **画像一致**：时区、语言、浏览器、出口 IP 全在这台机器里统一。

导出与复制：

```powershell
# 导出（先关机）
Stop-VM -Name ClaudeBox
Export-VM -Name ClaudeBox -Path "D:\VMExport"

# 复制一份做小号环境
Copy-Item "D:\VMExport\ClaudeBox" "D:\VMs\ClaudeBox2" -Recurse
Import-VM -Path "D:\VMs\ClaudeBox2\Virtual Machines\*.vmcx" -Copy -GenerateNewId
```

> 复制后记得改虚拟机名称、重新生成 MAC（`-GenerateNewId` 会做），并在系统里改主机名——两台一模一样的机器同时在线反而是个特征。
