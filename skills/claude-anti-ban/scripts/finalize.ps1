<#
.SYNOPSIS
    收尾自清理 · Windows
.DESCRIPTION
    Agent 干完活后清掉自己的中间产物，只留用户文档与用户数据备份。
    默认 DryRun；加 -Apply 执行。
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File finalize.ps1
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File finalize.ps1 -Apply -Iso "D:\ISO\Win10.iso"
#>
[CmdletBinding()]
param(
    [switch]$Apply,
    [string]$Iso,
    [string]$WorkDir = (Get-Location).Path
)

$ErrorActionPreference = 'SilentlyContinue'
$dry = -not $Apply

Write-Host '收尾自清理'
Write-Host ("模式：{0}" -f $(if ($dry) { 'DRY-RUN（只打印）' } else { 'APPLY' }))
Write-Host ('-' * 68)

$candidates = @(
    (Join-Path $WorkDir '.cab-state'),
    (Join-Path $WorkDir 'tmp-claude-anti-ban'),
    (Join-Path $WorkDir 'work-claude-anti-ban'),
    (Join-Path $WorkDir '__pycache__')
)
$candidates += Get-ChildItem -Path $WorkDir -File |
               Where-Object { $_.Name -match '^(cab-|tmp-|dbg-|scratch-).*\.(log|json|txt|ps1|py)$' } |
               ForEach-Object { $_.FullName }
if ($Iso) { $candidates += $Iso }

$found = @()
Write-Host '[Agent 产物]'
foreach ($c in $candidates) {
    if (-not (Test-Path -LiteralPath $c)) { continue }
    $size = if (Test-Path -LiteralPath $c -PathType Container) {
        [math]::Round((Get-ChildItem $c -Recurse -File -Force | Measure-Object Length -Sum).Sum / 1MB, 1)
    } else {
        [math]::Round((Get-Item $c).Length / 1MB, 1)
    }
    Write-Host ("  - {0,-44} {1} MB" -f $c, $size)
    $found += $c
}

Write-Host ''
Write-Host '[保留]'
foreach ($doc in @('Claude-使用手册.docx', 'Claude-使用手册.md', '用户手册.docx', '用户手册.md')) {
    $p = Join-Path $WorkDir $doc
    if (Test-Path $p) { Write-Host ("  OK {0}" -f $p) -ForegroundColor Green }
}
$backupRoot = 'D:\ClaudeBackups'
if (Test-Path $backupRoot) {
    $latest = Get-ChildItem $backupRoot -Directory | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    Write-Host ("  OK 用户数据备份：{0}" -f $latest.FullName) -ForegroundColor Green
}

Write-Host ''
if ($found.Count -eq 0) {
    Write-Host '没有需要清理的中间产物。'
    exit 0
}
if ($dry) {
    Write-Host 'DRY-RUN 结束。确认后加 -Apply 执行。'
    exit 0
}

Write-Host '执行中...'
foreach ($c in $found) {
    Remove-Item -LiteralPath $c -Recurse -Force -ErrorAction SilentlyContinue
    if (-not (Test-Path -LiteralPath $c)) { Write-Host ("  已删 {0}" -f $c) }
    else { Write-Host ("  失败 {0}" -f $c) -ForegroundColor Yellow }
}

Write-Host ''
Write-Host '[自检]'
$keep = @('Claude-使用手册.docx', 'Claude-使用手册.md', '用户手册.docx', '用户手册.md')
$leftover = Get-ChildItem $WorkDir -Force |
            Where-Object { $keep -notcontains $_.Name -and $_.Name -notmatch '^\.(git|gitignore)$' }
if ($leftover) {
    Write-Host '  仍有残留（请人工确认是否该留）：'
    $leftover | ForEach-Object { Write-Host ("    {0}" -f $_.Name) }
} else {
    Write-Host '  干净：只剩用户文档'
}

Write-Host ''
Write-Host '完成。用户只需要看：Claude-使用手册.docx'
