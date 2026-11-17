#!/usr/bin/env bash
# Claude 痕迹清理 · macOS
#
# 默认 dry-run：只打印会动什么，不删任何东西。
#
# 用法：
#   bash cleanup_traces.sh --dry-run                 # 默认
#   bash cleanup_traces.sh --apply                   # 备份 + 移入废纸篓
#   bash cleanup_traces.sh --apply --only browser    # 只清浏览器相关
#   bash cleanup_traces.sh --apply --only claude-code,claude-app
#   bash cleanup_traces.sh --apply --keychain        # 额外删 Claude Code 凭据
#
# 范围：all | browser | claude-code | claude-app | editor | system
# 安全：先备份到 ~/ClaudeBackups/<时间戳>/ 并生成 SHA-256 清单，
#       删除一律 mv 到 ~/.Trash/ClaudeCleanup-<时间戳>/，不做 rm -rf。
# 保护：projects / sessions / history.jsonl / file-history / skills / plugins /
#       hooks / commands / agents / mcp-servers / CLAUDE.md / settings.json
#       以及任何项目目录，一律不碰。

set -uo pipefail

APPLY=0
DO_KEYCHAIN=0
ONLY="all"

while [ $# -gt 0 ]; do
  case "$1" in
    --apply)    APPLY=1 ;;
    --dry-run)  APPLY=0 ;;
    --keychain) DO_KEYCHAIN=1 ;;
    --only)     shift; ONLY="${1:-all}" ;;
    -h|--help)  sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "未知参数: $1"; exit 64 ;;
  esac
  shift
done

if [ "$(uname -s)" != "Darwin" ]; then
  echo "此脚本针对 macOS。Linux 请参考 references/03a-cleanup-macos.md 手工执行。" >&2
  exit 64
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
BK="$HOME/ClaudeBackups/$STAMP"
TRASH="$HOME/.Trash/ClaudeCleanup-$STAMP"

# ---------- 目标定义 ----------
# 格式：scope|路径|说明
TARGETS=$(cat <<EOF
claude-code|$HOME/.claude/cache|Claude Code 缓存
claude-code|$HOME/.claude/stats-cache.json|统计缓存
claude-code|$HOME/.claude/telemetry|遥测队列
claude-code|$HOME/.claude/usage.jsonl|用量日志
claude-code|$HOME/.claude/usage.with-fix.jsonl|用量日志（修补版）
claude-code|$HOME/Library/Caches/claude-cli-nodejs|CLI 运行时缓存
claude-code|$HOME/.claude/ant-did|设备标识（可选，谨慎）
claude-code|$HOME/.claude/ant-device-registry.json|设备登记（可选，谨慎）
claude-app|$HOME/Library/Application Support/Claude|桌面端数据（含登录态）
claude-app|$HOME/Library/Caches/com.anthropic.claudefordesktop|桌面端缓存
claude-app|$HOME/Library/Preferences/com.anthropic.claudefordesktop.plist|桌面端偏好
claude-app|$HOME/Library/Logs/Claude|桌面端日志
EOF
)

# 保护清单：这些路径的前缀永远不动
PROTECTED=(
  "$HOME/.claude/projects"
  "$HOME/.claude/sessions"
  "$HOME/.claude/history.jsonl"
  "$HOME/.claude/file-history"
  "$HOME/.claude/skills"
  "$HOME/.claude/plugins"
  "$HOME/.claude/hooks"
  "$HOME/.claude/commands"
  "$HOME/.claude/agents"
  "$HOME/.claude/mcp-servers"
  "$HOME/.claude/CLAUDE.md"
  "$HOME/.claude/settings.json"
  "$HOME/.claude/settings.local.json"
  "$HOME/.claude/backups"
)

is_protected() {
  local p="$1"
  for pr in "${PROTECTED[@]}"; do
    case "$p" in "$pr"|"$pr"/*) return 0 ;; esac
  done
  return 1
}

scope_selected() {
  local s="$1"
  [ "$ONLY" = "all" ] && return 0
  case ",$ONLY," in *",$s,"*) return 0 ;; esac
  return 1
}

size_of() { du -sh "$1" 2>/dev/null | awk '{print $1}'; }

echo "Claude 痕迹清理 · macOS"
echo "模式：$([ "$APPLY" -eq 1 ] && echo 'APPLY（会真的动文件）' || echo 'DRY-RUN（只打印）')"
echo "范围：$ONLY"
echo "备份：$BK"
echo "废纸篓：$TRASH"
echo "────────────────────────────────────────────────────────"

PLAN=()
while IFS='|' read -r scope path desc; do
  [ -z "$scope" ] && continue
  scope_selected "$scope" || continue
  [ -e "$path" ] || continue
  if is_protected "$path"; then
    echo "[跳过·保护] $path"
    continue
  fi
  printf '[%s] %-8s %-10s %s\n' "计划" "$(size_of "$path")" "$scope" "$path"
  PLAN+=("$scope|$path|$desc")
done <<< "$TARGETS"

# 浏览器单独处理（不能整目录删）
if scope_selected browser; then
  echo
  echo "[浏览器] 需要单独处理以下位置（脚本不自动改浏览器数据库）："
  for prof in "$HOME/Library/Application Support/Google/Chrome/Default" \
              "$HOME/Library/Application Support/Google/Chrome/Profile "*; do
    [ -d "$prof" ] || continue
    echo "  - $prof"
    echo "      Cookies / Local Storage / IndexedDB / Service Worker / 站点权限"
    echo "      域名：claude.ai  anthropic.com  claude.com  withpersona.com"
  done
  echo "  建议用浏览器自带「站点数据管理」删除，比改数据库安全。"
  echo "  详见 references/03a-cleanup-macos.md 第 4.5 节。"
fi

# 需要精确匹配的零散目标：只列出来，让用户确认后手工处理（避免误删整个目录）
if scope_selected editor || scope_selected system; then
  echo
  echo "[零散目标] 下面这些需要按名字精确匹配，脚本不自动删，请确认后手工处理："
  for p in "$HOME/.vscode/extensions"/anthropic.* \
           "$HOME/Library/Application Support/Code/User/globalStorage"/anthropic.* \
           "$HOME/Library/Logs/DiagnosticReports"/Claude* \
           "$HOME/Library/Application Support/CrashReporter"/Claude* ; do
    [ -e "$p" ] && echo "  - $p  ($(size_of "$p"))"
  done
  echo "  命令示例：mv \"<上面的路径>\" \"$TRASH/\""
fi

echo
if [ ${#PLAN[@]} -eq 0 ]; then
  echo "没有匹配到需要清理的目标。"
  exit 0
fi

if [ "$APPLY" -eq 0 ]; then
  echo "DRY-RUN 结束。确认无误后加 --apply 执行。"
  echo "提醒：执行前请先退出 Claude 桌面端与 Claude Code。"
  exit 0
fi

# ---------- 检查进程 ----------
if pgrep -x "Claude" >/dev/null 2>&1; then
  echo "检测到 Claude 桌面端在运行，请先正常退出（不要强杀），然后重跑。" >&2
  exit 1
fi

# ---------- 备份 ----------
mkdir -p "$BK" && chmod 700 "$BK"
for entry in "${PLAN[@]}"; do
  IFS='|' read -r scope path desc <<< "$entry"
  rel="${path#"$HOME/"}"
  mkdir -p "$BK/$(dirname "$rel")"
  if [ -d "$path" ]; then
    rsync -a "$path/" "$BK/$rel/" 2>/dev/null
  else
    cp -p "$path" "$BK/$rel" 2>/dev/null
  fi
done
( cd "$BK" && find . -type f -exec shasum -a 256 {} \; > MANIFEST.sha256 2>/dev/null )
echo "备份完成：$BK（$(wc -l < "$BK/MANIFEST.sha256" | tr -d ' ') 个文件已校验）"

# ---------- 移入废纸篓 ----------
mkdir -p "$TRASH"
for entry in "${PLAN[@]}"; do
  IFS='|' read -r scope path desc <<< "$entry"
  if [ -e "$path" ]; then
    mv "$path" "$TRASH/" 2>/dev/null && echo "已移走: $path" || echo "失败: $path"
  fi
done

# ---------- 钥匙串（需显式 --keychain） ----------
if [ "$DO_KEYCHAIN" -eq 1 ]; then
  if security find-generic-password -s "Claude Code-credentials" >/dev/null 2>&1; then
    security delete-generic-password -s "Claude Code-credentials" >/dev/null 2>&1 \
      && echo "已删除钥匙串条目 Claude Code-credentials" \
      || echo "删除钥匙串条目失败（可能需要授权）"
  else
    echo "钥匙串中没有 Claude Code-credentials"
  fi
fi

# ---------- 系统层 ----------
if scope_selected system; then
  sudo dscacheutil -flushcache 2>/dev/null
  sudo killall -HUP mDNSResponder 2>/dev/null
  echo "已清 DNS 缓存"
  if grep -qiE "claude|anthropic" /etc/hosts 2>/dev/null; then
    echo "注意：/etc/hosts 里有 claude/anthropic 条目，请手工检查："
    grep -niE "claude|anthropic" /etc/hosts
  fi
  pbcopy < /dev/null 2>/dev/null && echo "已清空剪贴板"
fi

echo "────────────────────────────────────────────────────────"
echo "完成。"
echo "回滚：rsync -a \"$BK/\"\"\$HOME/\"  或从 $TRASH 里把目录拖回原位。"
echo "提醒：浏览器站点数据、凭据、支付/手机号/硬件指纹不在本脚本范围内。"
