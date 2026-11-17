<#
.SYNOPSIS
    Claude 环境自检 · Windows
.DESCRIPTION
    检查时区 / 语言 / IPv6 绑定 / DNS / 系统代理 / 出口 IP / ASN 属性 / Claude 连通性。
    只读，不修改任何设置。
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File check_env.ps1
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File check_env.ps1 -Quiet
#>
[CmdletBinding()]
param(
    [switch]$Quiet
)

$ErrorActionPreference = 'SilentlyContinue'
$script:Pass = 0; $script:Warn = 0; $script:Fail = 0

function Write-Item {
    param([string]$Status, [string]$Name, [string]$Value)
    switch ($Status) {
        'ok'   { $script:Pass++; if (-not $Quiet) { Write-Host "[OK]   " -ForegroundColor Green -NoNewline; Write-Host ("{0,-14} {1}" -f $Name, $Value) } }
        'warn' { $script:Warn++; if (-not $Quiet) { Write-Host "[WARN] " -ForegroundColor Yellow -NoNewline; Write-Host ("{0,-14} {1}" -f $Name, $Value) } }
        'fail' { $script:Fail++; if (-not $Quiet) { Write-Host "[FAIL] " -ForegroundColor Red -NoNewline; Write-Host ("{0,-14} {1}" -f $Name, $Value) } }
    }
}

function Write-Line { if (-not $Quiet) { Write-Host ('-' * 68) } }

Write-Line
if (-not $Quiet) {
    Write-Host "Claude 环境自检  ·  $(Get-Date -Format 'yyyy-MM-dd HH:mm')  ·  Windows" -ForegroundColor Cyan
}
Write-Line

# ---------- 1. 时区 ----------
$tz = (& tzutil /g) 2>$null
if (-not $tz) { $tz = (Get-TimeZone).Id }
switch -Regex ($tz) {
    'China Standard Time' { Write-Item 'fail' '系统时区' "$tz  <- 中国大陆时区，Claude Code 直接读这个" }
    '^$'                  { Write-Item 'warn' '系统时区' '读取失败' }
    default               { Write-Item 'ok'   '系统时区' $tz }
}

# ---------- 2. 语言 / 区域 ----------
$culture = (Get-WinSystemLocale).Name
$langs = (Get-WinUserLanguageList | ForEach-Object { $_.LanguageTag }) -join ', '
if ($langs -match '^zh-CN' -and $langs -notmatch 'en-US') {
    Write-Item 'warn' '首选语言' "$langs  <- 建议把 en-US 放第一位"
} else {
    Write-Item 'ok' '首选语言' $langs
}
Write-Item 'ok' '系统区域' $culture

# ---------- 3. IPv6 绑定 ----------
$v6 = Get-NetAdapterBinding -ComponentID ms_tcpip6 | Where-Object { $_.Enabled -and $_.Name -notmatch 'Loopback' }
if ($v6) {
    Write-Item 'warn' 'IPv6' ("已启用: " + (($v6 | ForEach-Object Name) -join ', ') + '  <- 可能绕过代理偷跑')
} else {
    Write-Item 'ok' 'IPv6' '所有网卡已禁用'
}

# ---------- 4. DNS ----------
$dns = (Get-DnsClientServerAddress -AddressFamily IPv4 |
        Where-Object { $_.ServerAddresses } |
        ForEach-Object { "$($_.InterfaceAlias):$($_.ServerAddresses -join '/')" }) -join '; '
if (-not $dns) { $dns = '未配置/自动获取' }
if ($dns -match '192\.168\.|10\.|172\.(1[6-9]|2[0-9]|3[01])\.') {
    Write-Item 'warn' 'DNS 服务器' "$dns  <- 本地/路由器 DNS，注意是否走代理"
} else {
    Write-Item 'ok' 'DNS 服务器' $dns
}

# ---------- 5. 系统代理 ----------
$reg = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
if ($reg.ProxyEnable -eq 1) {
    Write-Item 'ok' '系统代理' "$($reg.ProxyServer)"
} else {
    Write-Item 'warn' '系统代理' '未启用（若用 TUN 模式可忽略）'
}

# ---------- 6. 出口 IP ----------
$ip4 = $null; $geo = $null
try {
    $geo = Invoke-RestMethod -Uri 'https://ipinfo.io/json' -TimeoutSec 10 -Headers @{ 'User-Agent' = 'Mozilla/5.0'; 'Accept' = 'application/json' }
    $ip4 = $geo.ip
    Write-Item 'ok' '出口 IPv4' ("{0}  {1}, {2} {3}  {4}" -f $geo.ip, $geo.city, $geo.region, $geo.country, $geo.org)
} catch {
    try {
        $ip4 = (Invoke-RestMethod -Uri 'https://api.ipify.org' -TimeoutSec 10).Trim()
        Write-Item 'ok' '出口 IPv4' "$ip4  (ipinfo 不可用)"
    } catch {
        Write-Item 'fail' '出口 IPv4' "获取失败: $($_.Exception.Message)"
    }
}

# ---------- 7. Cloudflare 出口 ----------
$cfIp = $null
try {
    $trace = (Invoke-WebRequest -Uri 'https://www.cloudflare.com/cdn-cgi/trace' -TimeoutSec 10 -UseBasicParsing).Content
    ($trace -split "`n") | ForEach-Object { if ($_ -match '^ip=(.+)$') { $cfIp = $Matches[1].Trim() } }
    if ($cfIp -and $ip4 -and $cfIp -ne $ip4) {
        Write-Item 'fail' 'CF 出口' "$cfIp != $ip4  <- 分流失效或多出口"
    } else {
        Write-Item 'ok' 'CF 出口' "$cfIp（与默认出口一致）"
    }
} catch {
    Write-Item 'warn' 'CF 出口' "获取失败"
}

# ---------- 8. ASN / 属性 ----------
try {
    $api = Invoke-RestMethod -Uri 'http://ip-api.com/json/?fields=status,country,regionName,city,isp,org,as,hosting,proxy,mobile,timezone' -TimeoutSec 10
    if ($api.status -eq 'success') {
        $kind = if ($api.mobile) { '移动网络' } elseif ($api.hosting) { '机房/IDC' } else { '住宅/ISP' }
        if ($api.proxy) {
            Write-Item 'warn' 'IP 属性' "$kind  ASN $($api.as)  <- 被标记 proxy/vpn"
        } else {
            Write-Item 'ok' 'IP 属性' "$kind  ASN $($api.as)"
        }
        $ipTz = $api.timezone
        if ($ipTz -and $tz -and $ipTz -ne $tz) {
            Write-Item 'warn' '时区一致性' "IP 时区 $ipTz != 系统 $tz"
        } elseif ($ipTz) {
            Write-Item 'ok' '时区一致性' "一致（$ipTz）"
        }
    }
} catch {
    Write-Item 'warn' 'IP 属性' 'ip-api 查询失败（可能被限流）'
}

# ---------- 9. Claude 连通性 ----------
foreach ($url in @('https://claude.ai/', 'https://api.anthropic.com/')) {
    $host_ = $url -replace '^https://', '' -replace '/$', ''
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $resp = Invoke-WebRequest -Uri $url -TimeoutSec 15 -UseBasicParsing -MaximumRedirection 2
        $sw.Stop()
        Write-Item 'ok' $host_ ("HTTP {0}  {1:N0}ms" -f $resp.StatusCode, $sw.Elapsed.TotalMilliseconds)
    } catch {
        $sw.Stop()
        $code = $null
        if ($_.Exception.Response) { $code = [int]$_.Exception.Response.StatusCode }
        if ($code) {
            Write-Item 'ok' $host_ ("HTTP {0}  {1:N0}ms" -f $code, $sw.Elapsed.TotalMilliseconds)
        } else {
            Write-Item 'fail' $host_ ("连接失败: {0}" -f $_.Exception.Message)
        }
    }
}

# ---------- 10. Claude 客户端进程（提示用） ----------
$proc = Get-Process Claude -ErrorAction SilentlyContinue
if ($proc) { Write-Item 'ok' 'Claude 进程' ("运行中（{0} 个）" -f $proc.Count) }

Write-Line
$total = $script:Pass + $script:Warn + $script:Fail
if ($script:Fail -eq 0 -and $script:Warn -eq 0) {
    Write-Host "结论：$($script:Pass)/$total 全部通过" -ForegroundColor Green
    $rc = 0
} elseif ($script:Fail -eq 0) {
    Write-Host "结论：$($script:Pass) 通过 / $($script:Warn) 告警 / 0 失败" -ForegroundColor Yellow
    $rc = 1
} else {
    Write-Host "结论：$($script:Pass) 通过 / $($script:Warn) 告警 / $($script:Fail) 失败  <- 先修失败项" -ForegroundColor Red
    $rc = 2
}
if (-not $Quiet) {
    Write-Host "浏览器侧还需确认 WebRTC / Canvas / 时区指纹 -> https://ip.net.coffee/claude/" -ForegroundColor DarkGray
}
exit $rc
