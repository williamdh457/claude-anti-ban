#!/usr/bin/env bash
# 收尾自清理 · macOS / Linux
#
# Agent 干完活之后，把自己产生的中间产物清掉，只留：
#   1. Claude-使用手册.md / .docx   （给用户的那一份）
#   2. ~/ClaudeBackups/<stamp>/     （用户数据备份，不动）
#
# 用法：
#   bash finalize.sh                 # dry-run，只打印
#   bash finalize.sh --apply         # 执行
#   bash finalize.sh --apply --iso ~/Downloads/Win10.iso   # 顺带删掉装完的镜像
#
# 不删：用户文档、用户备份、代理客户端配置、任何项目目录。

set -uo pipefail

APPLY=0
ISO=""
KEEP_DOC=1

while [ $# -gt 0 ]; do
  case "$1" in
    --apply)  APPLY=1 ;;
    --iso)    shift; ISO="${1:-}" ;;
    --keep-doc) KEEP_DOC=1 ;;
    -h|--help) sed -n '2,14p' "$0"; exit 0 ;;
    *) echo "未知参数: $1"; exit 64 ;;
  esac
  shift
done

echo "收尾自清理"
[ "$APPLY" -eq 1 ] && echo "模式：APPLY" || echo "模式：DRY-RUN（只打印）"
echo "────────────────────────────────────────────────────────"

# ---------- 要清的（Agent 自己的产物） ----------
CANDIDATES=(
  ".cab-state"
  "tmp-claude-anti-ban"
  "work-claude-anti-ban"
  "__pycache__"
  "check_env.out"
  "ipcheck.json"
)

echo "[Agent 产物]"
FOUND=0
for c in "${CANDIDATES[@]}"; do
  if [ -e "$c" ]; then
    FOUND=1
    printf '  - %-28s %s\n' "$c" "$(du -sh "$c" 2>/dev/null | awk '{print $1}')"
  fi
done
# 临时日志 / 一次性脚本
while IFS= read -r f; do
  [ -n "$f" ] || continue
  FOUND=1
  printf '  - %-28s %s\n' "$f" "$(du -sh "$f" 2>/dev/null | awk '{print $1}')"
done < <(ls -1 2>/dev/null | grep -E '^(cab-|tmp-|dbg-|scratch-).*\.(log|json|txt|sh|py)$' || true)

if [ -n "$ISO" ] && [ -e "$ISO" ]; then
  FOUND=1
  printf '  - %-28s %s\n' "$ISO" "$(du -sh "$ISO" 2>/dev/null | awk '{print $1}')"
fi

# ---------- 要留的 ----------
echo
echo "[保留]"
for f in Claude-使用手册.md Claude-使用手册.docx 用户手册.md 用户手册.docx; do
  [ -e "$f" ] && printf '  ✓ %s\n' "$f"
done
if [ -d "$HOME/ClaudeBackups" ]; then
  latest="$(ls -1dt "$HOME/ClaudeBackups"/* 2>/dev/null | head -1)"
  printf '  ✓ 用户数据备份：%s\n' "${latest:-$HOME/ClaudeBackups}"
fi

echo
if [ "$FOUND" -eq 0 ]; then
  echo "没有需要清理的中间产物。"
  exit 0
fi

if [ "$APPLY" -eq 0 ]; then
  echo "DRY-RUN 结束。确认后加 --apply 执行。"
  exit 0
fi

# ---------- 执行 ----------
echo "执行中..."
for c in "${CANDIDATES[@]}"; do
  [ -e "$c" ] && rm -rf "$c" && echo "  已删 $c"
done
while IFS= read -r f; do
  [ -n "$f" ] || continue
  rm -f "$f" && echo "  已删 $f"
done < <(ls -1 2>/dev/null | grep -E '^(cab-|tmp-|dbg-|scratch-).*\.(log|json|txt|sh|py)$' || true)
if [ -n "$ISO" ] && [ -e "$ISO" ]; then
  rm -f "$ISO" && echo "  已删 $ISO"
fi

# ---------- 自检 ----------
echo
echo "[自检]"
leftover="$(ls -A 2>/dev/null | grep -vE '^(Claude-使用手册\.(md|docx)|用户手册\.(md|docx)|\.git|\.gitignore|README\.md|LICENSE|docs|skills|transcripts|_work)$' || true)"
if [ -n "$leftover" ]; then
  echo "  仍有残留（请人工确认是否该留）："
  printf '    %s\n' "$leftover"
else
  echo "  干净：只剩用户文档与仓库文件"
fi

echo
echo "完成。用户只需要看：Claude-使用手册.docx"
