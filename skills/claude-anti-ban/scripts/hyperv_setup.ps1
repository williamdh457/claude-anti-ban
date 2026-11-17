<#
.SYNOPSIS
    一键准备 Hyper-V 与 Claude 专用干净虚拟机
.DESCRIPTION
    按顺序执行：检查系统版本 / CPU 虚拟化 / 资源 -> 开启 Hyper-V 功能
    -> 确认虚拟交换机 -> 创建虚拟机 -> 挂载 ISO -> 关闭自动检查点 -> 启动。
    幂等：已存在的虚拟机不会重建；已开启的功能不会重复开启。
    需以管理员身份运行。
.PARAMETER IsoPath
    Windows 安装 ISO 的完整路径（必填）
.PARAMETER Name
    虚拟机名称，默认 ClaudeBox
.PARAMETER VMPath
    虚拟机存放目录，默认 D:\VMs
.PARAMETER MemoryGB
    启动内存（GB），默认 6
.PARAMETER DiskGB
    虚拟硬盘大小（GB），默认 80
.PARAMETER SwitchName
    虚拟交换机，默认 Default Switch
.PARAMETER Generation
    虚拟机代数，1 或 2，默认 1（装 Win10 用 1）
.PARAMETER DryRun
    只打印计划，不做任何修改
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File hyperv_setup.ps1 -IsoPath "D:\ISO\Win10.iso" -DryRun
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File hyperv_setup.ps1 -IsoPath "D:\ISO\Win10.iso" -MemoryGB 8
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$IsoPath,
    [string]$Name = 'ClaudeBox',
    [string]$VMPath = 'D:\VMs',
    [int]$MemoryGB = 6,
    [int]$DiskGB = 80,
    [string]$SwitchName = 'Default Switch',
    [ValidateSet(1, 2)]
    [int]$Generation = 1,
    [switch]$DryRun,
    [switch]$NoStart
)

$ErrorActionPreference = 'Stop'

function Write-Step { param($m) Write-Host "`n==> $m" -ForegroundColor Cyan }
function Write-Ok   { param($m) Write-Host "    [OK] $m" -ForegroundColor Green }
function Write-Warn2{ param($m) Write-Host "    [!!] $m" -ForegroundColor Yellow }
function Write-Bad  { param($m) Write-Host "    [XX] $m" -ForegroundColor Red }

# ---------- 0. 管理员 ----------
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
           ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Bad '需要管理员权限。请右键 PowerShell -> 以管理员身份运行。'
    exit 1
}

Write-Step '环境检查'

# ---------- 1. Windows 版本 ----------
$os = Get-CimInstance Win32_OperatingSystem
$caption = $os.Caption
Write-Host "    系统: $caption ($($os.Version))"
$isHome = $caption -match 'Home|家庭'
if ($isHome) {
    Write-Warn2 '检测到家庭版：官方不支持 Hyper-V。'
    Write-Host '    方案一（推荐）：设置 -> 系统 -> 激活 -> 更改产品密钥，升级到专业版后重跑。'
    Write-Host '    方案二：改用宿主机方案（见 references/13-vm-or-host.md）。'
    if (-not $DryRun) { exit 1 }
}

# ---------- 2. CPU 虚拟化 ----------
$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
$vfw = $cpu.VirtualizationFirmwareEnabled
Write-Host "    CPU: $($cpu.Name)  核心 $($cpu.NumberOfCores)  虚拟化固件: $vfw"
if ($vfw -eq $false) {
    Write-Bad 'BIOS 里未开启虚拟化（VT-x / AMD-V / SVM）。请进 BIOS 开启后重试。'
    if (-not $DryRun) { exit 1 }
}

# ---------- 3. 内存 / 磁盘 ----------
$memGB = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
Write-Host "    物理内存: $memGB GB"
if ($memGB -lt ($MemoryGB + 4)) {
    Write-Warn2 "内存偏紧：给虚拟机 $MemoryGB GB 后，宿主机只剩 $([math]::Round($memGB - $MemoryGB,1)) GB。建议 16 GB 以上。"
}

$drive = (Split-Path $VMPath -Qualifier)
if ($drive) {
    $free = [math]::Round((Get-PSDrive $drive.TrimEnd(':')).Free / 1GB, 1)
    Write-Host "    $drive 可用空间: $free GB"
    if ($free -lt ($DiskGB + 20)) { Write-Warn2 "磁盘可能不够：需要约 $($DiskGB + 20) GB。" }
}

# ---------- 4. Hyper-V 功能 ----------
Write-Step 'Hyper-V 功能'
$feat = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All
if ($feat.State -eq 'Enabled') {
    Write-Ok 'Hyper-V 已启用'
} else {
    Write-Host "    当前状态: $($feat.State)"
    if ($DryRun) {
        Write-Warn2 'DRY-RUN：将执行 Enable-WindowsOptionalFeature -FeatureName Microsoft-Hyper-V-All（需要重启）'
    } else {
        Write-Host '    正在启用 Hyper-V（可能需要几分钟）...'
        Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All -All -NoRestart | Out-Null
        $feat2 = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All
        if ($feat2.State -ne 'Enabled') {
            Write-Bad '启用后状态仍不是 Enabled，通常需要重启。请重启后重新运行本脚本。'
            exit 2
        }
        Write-Ok 'Hyper-V 已启用'
    }
}

# 服务
$svc = Get-Service vmms, vmcompute -ErrorAction SilentlyContinue
foreach ($s in $svc) { Write-Host "    服务 $($s.Name): $($s.Status)" }

# ---------- 5. ISO ----------
Write-Step '安装镜像'
if (-not (Test-Path -LiteralPath $IsoPath)) {
    Write-Bad "找不到 ISO: $IsoPath"
    Write-Host '    用微软官方 Media Creation Tool 生成：为另一台电脑创建安装介质 -> ISO 文件。'
    exit 1
}
$iso = Get-Item -LiteralPath $IsoPath
Write-Ok ("{0}  ({1:N1} GB)" -f $iso.FullName, ($iso.Length / 1GB))

# ---------- 6. 虚拟交换机 ----------
Write-Step '虚拟交换机'
$sw = Get-VMSwitch -Name $SwitchName -ErrorAction SilentlyContinue
if ($sw) {
    Write-Ok "已存在: $SwitchName ($($sw.SwitchType))"
} else {
    if ($DryRun) {
        Write-Warn2 "DRY-RUN：将创建 Internal 交换机 $SwitchName 并配置 NAT"
    } else {
        Write-Host "    未找到 $SwitchName，创建 Internal 交换机 + NAT ..."
        New-VMSwitch -Name $SwitchName -SwitchType Internal | Out-Null
        $ifAlias = "vEthernet ($SwitchName)"
        $ip = (Get-NetIPAddress -InterfaceAlias $ifAlias -AddressFamily IPv4 -ErrorAction SilentlyContinue)
        if (-not $ip) {
            New-NetIPAddress -IPAddress 192.168.137.1 -PrefixLength 24 -InterfaceAlias $ifAlias | Out-Null
        }
        if (-not (Get-NetNat -Name "ClaudeNAT" -ErrorAction SilentlyContinue)) {
            New-NetNat -Name "ClaudeNAT" -InternalIPInterfaceAddressPrefix 192.168.137.0/24 | Out-Null
        }
        Write-Ok "已创建 $SwitchName (192.168.137.0/24 + NAT ClaudeNAT)"
    }
}

# ---------- 7. 虚拟机 ----------
Write-Step "虚拟机 $Name"
$vm = Get-VM -Name $Name -ErrorAction SilentlyContinue
if ($vm) {
    Write-Ok "已存在，跳过创建（当前状态: $($vm.State)）"
} else {
    if ($DryRun) {
        Write-Warn2 "DRY-RUN：将创建 Gen$Generation / $MemoryGB GB / $DiskGB GB / $SwitchName"
    } else {
        if (-not (Test-Path -LiteralPath $VMPath)) { New-Item -ItemType Directory -Force -Path $VMPath | Out-Null }
        $vhdDir = Join-Path $VMPath $Name
        if (-not (Test-Path -LiteralPath $vhdDir)) { New-Item -ItemType Directory -Force -Path $vhdDir | Out-Null }

        New-VM -Name $Name `
               -Path $VMPath `
               -MemoryStartupBytes ($MemoryGB * 1GB) `
               -Generation $Generation `
               -NewVHDPath (Join-Path $vhdDir "$Name.vhdx") `
               -NewVHDSizeBytes ($DiskGB * 1GB) `
               -SwitchName $SwitchName | Out-Null
        Write-Ok '虚拟机已创建'
    }
}

if (-not $DryRun -and (Get-VM -Name $Name -ErrorAction SilentlyContinue)) {
    Write-Step '配置虚拟机'
    Set-VM -Name $Name -AutomaticCheckpointsEnabled $false
    Set-VM -Name $Name -MemoryStartupBytes ($MemoryGB * 1GB)
    Set-VMProcessor -VMName $Name -Count ([math]::Max(2, [math]::Min(4, [Environment]::ProcessorCount / 2)))
    Add-VMDvdDrive -VMName $Name -Path $IsoPath -ErrorAction SilentlyContinue
    $dvd = Get-VMDvdDrive -VMName $Name | Select-Object -First 1
    Set-VMFirmware -VMName $Name -FirstBootDevice $dvd -ErrorAction SilentlyContinue
    Write-Ok "自动检查点已关闭；内存 $MemoryGB GB；ISO 已挂载"

    if ($Generation -eq 2) {
        Write-Host '    Gen2：如需装 Win11，还需 TPM + 安全启动：'
        Write-Host "      Set-VMKeyProtector -VMName $Name -NewLocalKeyProtector"
        Write-Host "      Enable-VMTPM -VMName $Name"
        Write-Host "      Set-VMFirmware -VMName $Name -EnableSecureBoot On"
    }

    Write-Step '启动'
    if (-not $NoStart) {
        if ((Get-VM -Name $Name).State -eq 'Off') { Start-VM -Name $Name }
        Write-Ok "已启动。正在打开控制台窗口..."
        Start-Process vmconnect.exe -ArgumentList "localhost `"$Name`""
    } else {
        Write-Warn2 '已跳过启动（-NoStart）'
    }
}

Write-Step '完成'
Write-Host @"
接下来（在虚拟机窗口里）：
  1. Press any key -> 现在安装 -> 我没有产品密钥 -> Windows 10 专业版
  2. 自定义安装 -> 选未分配空间 -> 下一步
  3. 区域选 United States，键盘 US，用本地账户（不要微软账户）
  4. 进系统后：tzutil /s "Eastern Standard Time"
  5. 关 IPv6：Disable-NetAdapterBinding -Name "Ethernet" -ComponentID ms_tcpip6
  6. 装代理客户端并开 TUN，导入 Claude 分流规则
  7. 只装：浏览器 / VSCode / Claude 桌面端
  8. Hyper-V 管理器 -> 右键 -> 检查点 -> 命名 clean-baseline
"@ -ForegroundColor DarkGray
