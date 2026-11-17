# 03b · 痕迹清理 · Windows

> 原则同 macOS：**先审计、再备份、删除进回收站，不永久删。**
> Windows 比 macOS 多三个坑：**注册表、凭据管理器、WSL 里的第二套 `~/.claude`**。

---

## 一、审计（只读）

```powershell
# 1) 系统身份面
(Get-ComputerInfo).WindowsProductName
tzutil /g
Get-WinSystemLocale | Select Name, DisplayName
Get-WinUserLanguageList | Select LanguageTag
Get-NetAdapterBinding -ComponentID ms_tcpip6 | Select Name, Enabled

# 2) Claude 数据体积
$paths = @(
  "$env:APPDATA\Claude",
  "$env:LOCALAPPDATA\AnthropicClaude",
  "$env:LOCALAPPDATA\claude-code",
  "$env:USERPROFILE\.claude",
  "$env:USERPROFILE\.claude.json",
  "$env:APPDATA\Code\User\globalStorage",
  "$env:USERPROFILE\.vscode\extensions"
)
foreach ($p in $paths) {
  if (Test-Path $p) {
    $size = (Get-ChildItem $p -Recurse -Force -ErrorAction SilentlyContinue |
             Measure-Object Length -Sum).Sum / 1MB
    "{0,-60} {1,8:N1} MB" -f $p, $size
  } else { "{0,-60} (不存在)" -f $p }
}

# 3) 凭据管理器
cmdkey /list | Select-String -Pattern "claude" -Context 0,1

# 4) 浏览器 Profile
Get-ChildItem "$env:LOCALAPPDATA\Google\Chrome\User Data" -Directory |
  Where-Object Name -match '^(Default|Profile)' | Select Name
Get-ChildItem "$env:LOCALAPPDATA\Microsoft\Edge\User Data" -Directory |
  Where-Object Name -match '^(Default|Profile)' | Select Name

# 5) 是否有 WSL 里的第二套
wsl -l -v
```

---

## 二、保护清单（绝对不动）

```
%USERPROFILE%\.claude\projects\
%USERPROFILE%\.claude\sessions\
%USERPROFILE%\.claude\history.jsonl
%USERPROFILE%\.claude\file-history\
%USERPROFILE%\.claude\skills\  plugins\  hooks\  commands\  agents\  mcp-servers\
%USERPROFILE%\.claude\CLAUDE.md
%USERPROFILE%\.claude\settings.json  settings.local.json
%USERPROFILE%\.claude\backups\
任何项目目录、Git 仓库
浏览器书签、历史、密码、其他站点数据
```

---

## 三、备份

```powershell
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$bk = "D:\ClaudeBackups\$stamp"
New-Item -ItemType Directory -Force -Path $bk | Out-Null

# 复制目标目录
Copy-Item "$env:USERPROFILE\.claude" "$bk\dot-claude" -Recurse -Force -ErrorAction SilentlyContinue
Copy-Item "$env:USERPROFILE\.claude.json" "$bk\" -Force -ErrorAction SilentlyContinue
Copy-Item "$env:APPDATA\Claude" "$bk\appdata-Claude" -Recurse -Force -ErrorAction SilentlyContinue

# 校验清单
Get-ChildItem $bk -Recurse -File | Get-FileHash -Algorithm SHA256 |
  Select Path, Hash | Export-Csv "$bk\MANIFEST.csv" -NoTypeInformation -Encoding UTF8
(Get-ChildItem $bk -Recurse -File).Count
```

> 备份放非系统盘（`D:\`），不要放 OneDrive 同步目录。

---

## 四、分层清理

### 4.1 可再生的缓存 / 日志（安全）

```powershell
$trash = "D:\ClaudeCleanup-$stamp"
New-Item -ItemType Directory -Force -Path $trash | Out-Null

$cacheTargets = @(
  "$env:USERPROFILE\.claude\cache",
  "$env:USERPROFILE\.claude\stats-cache.json",
  "$env:USERPROFILE\.claude\telemetry",
  "$env:USERPROFILE\.claude\usage.jsonl",
  "$env:LOCALAPPDATA\claude-code\Cache",
  "$env:LOCALAPPDATA\claude-code\logs",
  "$env:LOCALAPPDATA\AnthropicClaude\Cache",
  "$env:LOCALAPPDATA\AnthropicClaude\logs"
)
foreach ($p in $cacheTargets) {
  if (Test-Path $p) { Move-Item $p $trash -Force; "moved: $p" }
}
```

### 4.2 桌面端登录态与数据

```powershell
# 正常退出（不要 Stop-Process -Force）
Get-Process Claude -ErrorAction SilentlyContinue | ForEach-Object { $_.CloseMainWindow() | Out-Null }
Start-Sleep 3
Get-Process Claude -ErrorAction SilentlyContinue | Select Id, ProcessName
# 仍有残留再逐个结束（确认窗口已关）
# Get-Process Claude | Stop-Process

Move-Item "$env:APPDATA\Claude" "$trash\appdata-Claude" -Force -ErrorAction SilentlyContinue
Move-Item "$env:LOCALAPPDATA\AnthropicClaude" "$trash\localappdata-AnthropicClaude" -Force -ErrorAction SilentlyContinue
```

> **不要用「设置 → 应用 → Claude → 重置」**。重置会删掉登录态 + 本地配置 + 历史记录，而且不给你备份机会。要清就按上面手动移走。
> 客户端只是打不开（不是要清数据）时用 **终止 → 修复**，别点重置。

### 4.3 Claude Code 凭据与账号字段

```powershell
# 官方登出
claude logout 2>$null

# 凭据管理器删除
cmdkey /list | Select-String "claude"          # 先看条目名
cmdkey /delete:"Claude Code"                   # 按实际名称删
# 或 GUI：控制面板 → 凭据管理器 → Windows 凭据 → 找到 Claude → 删除

# 账号字段（只改白名单键）
$p = "$env:USERPROFILE\.claude.json"
if (Test-Path $p) {
  $d = Get-Content $p -Raw | ConvertFrom-Json
  $bytes = New-Object byte[] 32
  [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
  $newId = ($bytes | ForEach-Object { $_.ToString("x2") }) -join ""
  if ($d.PSObject.Properties.Name -contains 'userID')    { $d.userID = $newId }
  if ($d.PSObject.Properties.Name -contains 'machineID') { $d.machineID = $newId }
  foreach ($k in @('oauthAccount','accountUuid','organizationUuid')) {
    if ($d.PSObject.Properties.Name -contains $k) { $d.PSObject.Properties.Remove($k) }
  }
  $d | ConvertTo-Json -Depth 20 | Set-Content $p -Encoding UTF8
  "已更新 $p"
}
```

> 只动这几个键。`projects` / `mcpServers` / `settings` 保留。

### 4.4 设备记录（单独授权）

```powershell
foreach ($f in @("$env:USERPROFILE\.claude\ant-did",
                 "$env:USERPROFILE\.claude\ant-device-registry.json")) {
  if (Test-Path $f) { Move-Item $f $trash -Force; "moved: $f" }
}
```

### 4.5 浏览器

**优先用浏览器设置界面**（最安全、不会破坏 Profile）：

```
Chrome/Edge → 设置 → 隐私、搜索和服务 → 第三方 Cookie → 查看所有站点数据
→ 搜索 anthropic / claude → 删除
```

命令行方式（浏览器完全退出后，先备份 `Cookies` 文件）：

```powershell
$profiles = Get-ChildItem "$env:LOCALAPPDATA\Google\Chrome\User Data" -Directory |
            Where-Object Name -match '^(Default|Profile)'
foreach ($pr in $profiles) {
  $cookie = Join-Path $pr.FullName "Network\Cookies"
  if (-not (Test-Path $cookie)) { $cookie = Join-Path $pr.FullName "Cookies" }
  if (Test-Path $cookie) {
    Copy-Item $cookie "$trash\$($pr.Name)-Cookies.bak" -Force
    "备份: $cookie"
    # 删除记录需要 sqlite3（Windows 不自带，可用 WSL 或 python 的 sqlite3 模块）
  }
}
```

用 Python（Windows 自带 `py` 或装了 Python）：

```powershell
python -c @"
import sqlite3, glob, os
pats = ['%claude.ai%','%anthropic.com%','%claude.com%','%withpersona.com%']
for db in glob.glob(os.path.expandvars(r'%LOCALAPPDATA%\Google\Chrome\User Data\*\Network\Cookies')):
    con = sqlite3.connect(db)
    cur = con.cursor()
    for p in pats:
        cur.execute('DELETE FROM cookies WHERE host_key LIKE ?', (p,))
    con.commit()
    print(db, 'remaining:', cur.execute('SELECT COUNT(*) FROM cookies').fetchone()[0])
    con.close()
"@
```

**注意**：

- 不要按文件名含 `claude` 整目录删（会误删仓库、书签、其他应用数据）；
- LevelDB（Local Storage / IndexedDB）不要文本搜索后整库删，用浏览器界面删；
- 多 Profile 逐个处理；
- Edge 路径把 `Google\Chrome` 换成 `Microsoft\Edge`。

### 4.6 编辑器

```powershell
Remove-Item "$env:USERPROFILE\.vscode\extensions\anthropic.*" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item "$env:APPDATA\Code\User\globalStorage\anthropic.*" -Recurse -Force -ErrorAction SilentlyContinue
```

### 4.7 注册表 / 系统层

```powershell
# 卸载残留（只查，不盲删）
Get-ItemProperty HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* |
  Where-Object DisplayName -match "Claude|Anthropic" | Select DisplayName, UninstallString

# 开机自启残留
Get-CimInstance Win32_StartupCommand | Where-Object Command -match "Claude"

# DNS 缓存
ipconfig /flushdns

# hosts 残留
Select-String -Path "$env:SystemRoot\System32\drivers\etc\hosts" -Pattern "claude|anthropic"

# 系统代理残留
Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings" |
  Select ProxyEnable, ProxyServer

# 剪贴板
Set-Clipboard -Value " "
```

### 4.8 WSL 里的第二套（容易漏）

如果你在 WSL 里也跑过 Claude Code：

```powershell
wsl -d <发行版> -- bash -lc 'ls -la ~/.claude ~/.claude.json 2>/dev/null'
wsl -d <发行版> -- bash -lc 'mv ~/.claude ~/.claude.bak.$(date +%s) 2>/dev/null; mv ~/.claude.json ~/.claude.json.bak 2>/dev/null'
```

---

## 五、验收

```powershell
# 1) 目标路径不存在
Test-Path "$env:APPDATA\Claude", "$env:LOCALAPPDATA\AnthropicClaude", "$env:USERPROFILE\.claude\cache"

# 2) 保护路径完好
Test-Path "$env:USERPROFILE\.claude\projects", "$env:USERPROFILE\.claude\settings.json"

# 3) 凭据
cmdkey /list | Select-String "claude"

# 4) Cookie
python -c "import sqlite3,glob,os;[print(d, sqlite3.connect(d).execute(\"select count(*) from cookies where host_key like '%claude%' or host_key like '%anthropic%'\").fetchone()) for d in glob.glob(os.path.expandvars(r'%LOCALAPPDATA%\Google\Chrome\User Data\*\Network\Cookies'))]"

# 5) 备份
Get-ChildItem "D:\ClaudeBackups\$stamp" | Select Name, Length
```

---

## 六、回滚

```powershell
Copy-Item "D:\ClaudeBackups\$stamp\dot-claude\*" "$env:USERPROFILE\.claude\" -Recurse -Force
Copy-Item "D:\ClaudeBackups\$stamp\.claude.json" "$env:USERPROFILE\" -Force
Copy-Item "D:\ClaudeBackups\$stamp\appdata-Claude" "$env:APPDATA\Claude" -Recurse -Force

# 或者从回收站还原
Start-Process "shell:RecycleBinFolder"
```

---

## 七、清不掉的东西

| 标识 | 说明 |
|---|---|
| 支付卡 BIN / 卡号 | 服务端记录 |
| 手机号 / 邮箱 | 永久绑定 |
| 硬件指纹 | 主板/CPU/GPU 序列号、MachineGuid、磁盘序列号、屏幕组合 |
| `MachineGuid` | `HKLM\SOFTWARE\Microsoft\Cryptography\MachineGuid`，改它会影响激活和其他软件，**不建议动** |
| ISP 分配记录 | 运营商侧 |
| 服务端风控历史 | 无法访问 |

> 有些人会改 `MachineGuid` 想「换机器」。副作用大（Windows 激活、部分软件授权失效），收益不确定。**换设备或换虚拟机更干净。**

---

## 八、常见错误

| 错误 | 后果 | 正确做法 |
|---|---|---|
| 点「重置」清 Claude 客户端 | 数据全没，无备份 | 手动移走目录 |
| `Remove-Item -Recurse -Force` 直接删 | 不可恢复 | 先 `Move-Item` 到备份盘 |
| 删 `%USERPROFILE%\.claude` 整个目录 | projects/skills/hooks 全没 | 只移 cache/logs |
| 忽略 WSL 里的 `~/.claude` | 清了一半 | 两个系统都清 |
| 改 MachineGuid | 激活失效 | 别动 |
| 备份放 OneDrive | 同步泄露 token | 放本地非同步盘 |
| 以为清完就无痕 | 硬件与支付层仍在 | 换身份要素 |
