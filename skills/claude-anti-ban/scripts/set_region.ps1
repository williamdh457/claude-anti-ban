<#
.SYNOPSIS
    一键把 Windows 的时区 / 区域 / 语言 / IPv6 / 自动校时 调成与出口一致
.DESCRIPTION
    按出口 IP 所在地区设置系统身份面，减少「IP 在海外、系统说中国」这类矛盾。
    默认 DryRun，加 -Apply 才执行。需要管理员权限（改时区和网卡绑定）。
.PARAMETER TimeZone
    时区。支持 IANA（America/New_York）或 Windows ID（Eastern Standard Time）。
    不填则按 -FromIp 自动推断。
.PARAMETER FromIp
    按出口 IP 自动推断时区（默认开启）。用 -NoAutoDetect 关闭。
.PARAMETER Region
    区域格式，默认 en-US。
.PARAMETER Language
    首选语言，默认 en-US。
.PARAMETER DisableIPv6
    关闭所有网卡的 IPv6 绑定。
.PARAMETER DisableAutoTime
    关闭「自动设置时间 / 自动设置时区」。
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File set_region.ps1
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File set_region.ps1 -Apply
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File set_region.ps1 -TimeZone Asia/Singapore -Apply
#>
[CmdletBinding()]
param(
    [string]$TimeZone,
    [switch]$NoAutoDetect,
    [string]$Region = 'en-US',
    [string]$Language = 'en-US',
    [switch]$DisableIPv6,
    [switch]$DisableAutoTime,
    [switch]$Apply
)

$ErrorActionPreference = 'Continue'
$dry = -not $Apply

# IANA -> Windows 映射
$map = @{
    'Asia/Shanghai'         = 'China Standard Time'
    'Asia/Singapore'        = 'Singapore Standard Time'
    'Asia/Taipei'           = 'Taipei Standard Time'
    'Asia/Tokyo'            = 'Tokyo Standard Time'
    'Asia/Seoul'            = 'Korea Standard Time'
    'Asia/Hong_Kong'        = 'China Standard Time'
    'America/New_York'      = 'Eastern Standard Time'
    'America/Chicago'       = 'Central Standard Time'
    'America/Denver'        = 'Mountain Standard Time'
    'America/Phoenix'       = 'US Mountain Standard Time'
    'America/Los_Angeles'   = 'Pacific Standard Time'
    'America/Anchorage'     = 'Alaskan Standard Time'
    'Pacific/Honolulu'      = 'Hawaiian Standard Time'
    'Europe/London'         = 'GMT Standard Time'
    'Europe/Paris'          = 'Romance Standard Time'
    'Europe/Berlin'         = 'W. Europe Standard Time'
    'Europe/Amsterdam'      = 'W. Europe Standard Time'
    'Australia/Sydney'      = 'AUS Eastern Standard Time'
    'UTC'                   = 'UTC'
}

function Say($msg, $color = 'Gray') { Write-Host $msg -ForegroundColor $color }

Say 'Claude 区域一致性设置 · Windows'
Say ("模式：{0}" -f $(if ($dry) { 'DRY-RUN（只打印）' } else { 'APPLY' })) 'Cyan'
Say ('-' * 68)

# ---------- 1. 决定时区 ----------
$target = $TimeZone
if (-not $target -and -not $NoAutoDetect) {
    try {
        $geo = Invoke-RestMethod -Uri 'https://ipinfo.io/json' -TimeoutSec 10 -Headers @{ Accept = 'application/json' }
        Say ("出口 IP: {0}  {1}, {2} {3}" -f $geo.ip, $geo.city, $geo.region, $geo.country)
        # ipinfo 不直接给 IANA 时区，用 ip-api 补
        $api = Invoke-RestMethod -Uri 'http://ip-api.com/json/?fields=timezone,country,city' -TimeoutSec 10
        if ($api.timezone) {
            $target = $api.timezone
            Say ("按出口推断时区: {0}" -f $target) 'Yellow'
        }
    } catch {
        Say '自动推断失败，请用 -TimeZone 手动指定' 'Yellow'
    }
}
if (-not $target) {
    Say '未指定时区。示例：-TimeZone America/New_York 或 -TimeZone Asia/Singapore' 'Red'
    exit 64
}

$winTz = $target
if ($map.ContainsKey($target)) { $winTz = $map[$target] }
$valid = Get-TimeZone -ListAvailable | Where-Object { $_.Id -eq $winTz }
if (-not $valid) {
    Say ("无效的 Windows 时区 ID: {0}" -f $winTz) 'Red'
    Say ('可用示例: ' + (($map.Values | Sort-Object -Unique) -join ', '))
    exit 64
}

if ($target -match 'Asia/Shanghai|Asia/Urumqi|Asia/Chongqing') {
    Say '警告：你选的是中国大陆时区。若出口在海外，这会构成明显矛盾。' 'Red'
}

Say ''
Say ("[计划] 时区      -> {0}  ({1})" -f $winTz, $target)
Say ("[计划] 区域格式  -> {0}" -f $Region)
Say ("[计划] 首选语言  -> {0}（加到列表第一位）" -f $Language)
if ($DisableAutoTime) { Say '[计划] 关闭「自动设置时间/时区」' }
if ($DisableIPv6)     { Say '[计划] 关闭所有网卡 IPv6 绑定' }

if ($dry) {
    Say ''
    Say 'DRY-RUN 结束。确认后加 -Apply 执行。' 'Yellow'
    exit 0
}

# ---------- 2. 执行 ----------
Say ''
Say '执行中...' 'Cyan'

try {
    Set-TimeZone -Id $winTz
    Say ("[OK] 时区 = {0}" -f (Get-TimeZone).Id) 'Green'
} catch { Say ("[XX] 设置时区失败: {0}" -f $_.Exception.Message) 'Red' }

try {
    Set-Culture -CultureInfo $Region
    Say ("[OK] 区域格式 = {0}" -f (Get-Culture).Name) 'Green'
} catch { Say ("[XX] 设置区域失败: {0}" -f $_.Exception.Message) 'Red' }

try {
    $list = Get-WinUserLanguageList
    $list.Insert(0, (New-WinUserLanguageList $Language)[0])
    $list = $list | Select-Object -Unique -Property LanguageTag
    Set-WinUserLanguageList -LanguageList $list -Force
    Say ("[OK] 首选语言 = {0}" -f ((Get-WinUserLanguageList | ForEach-Object LanguageTag) -join ', ')) 'Green'
} catch { Say ("[XX] 设置语言失败: {0}" -f $_.Exception.Message) 'Red' }

if ($DisableAutoTime) {
    try {
        Set-Service w32time -StartupType Disabled -ErrorAction SilentlyContinue
        Stop-Service w32time -Force -ErrorAction SilentlyContinue
        $k = 'HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Parameters'
        Set-ItemProperty -Path $k -Name 'Type' -Value 'NoSync' -ErrorAction SilentlyContinue
        # 关闭「自动设置时区」
        $tz = 'HKLM:\SYSTEM\CurrentControlSet\Services\tzautoupdate'
        if (Test-Path $tz) { Set-ItemProperty -Path $tz -Name 'Start' -Value 4 }
        Say '[OK] 已关闭自动校时 / 自动时区' 'Green'
    } catch { Say ("[XX] 关闭自动校时失败: {0}" -f $_.Exception.Message) 'Red' }
}

if ($DisableIPv6) {
    try {
        $adapters = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' -and $_.Name -notmatch 'Loopback' }
        foreach ($a in $adapters) {
            Disable-NetAdapterBinding -Name $a.Name -ComponentID ms_tcpip6 -ErrorAction SilentlyContinue
            Say ("[OK] 已关闭 IPv6: {0}" -f $a.Name) 'Green'
        }
    } catch { Say ("[XX] 关闭 IPv6 失败: {0}" -f $_.Exception.Message) 'Red' }
}

Say ''
Say '验收：' 'Cyan'
Say '  tzutil /g'
Say '  Get-WinSystemLocale'
Say '  Get-NetAdapterBinding -ComponentID ms_tcpip6'
Say '  curl.exe -4 https://ipinfo.io/ip'
Say '然后重启浏览器，打开 https://ip.net.coffee/claude/ 看「时区一致」与「语言」。'
