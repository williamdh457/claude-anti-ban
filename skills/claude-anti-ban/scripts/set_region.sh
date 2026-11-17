#!/usr/bin/env bash
# Claude 区域一致性设置 · macOS / Linux
#
# 把时区 / 区域 / 语言 / IPv6 / 自动校时 调成与出口一致。
# 默认 dry-run，加 --apply 才执行。
#
# 用法：
#   bash set_region.sh                        # 自动按出口 IP 推断时区，只打印
#   bash set_region.sh --apply                # 执行
#   bash set_region.sh --tz Asia/Singapore --apply
#   bash set_region.sh --tz America/New_York --no-ipv6-off --apply
#
# 注意：改系统时区在 macOS 上需要 sudo（脚本会提示你输入密码，不保存）。

set -uo pipefail

APPLY=0
TZ_TARGET=""
DO_IPV6=1
DO_NTP=1
DO_LOCALE=1

while [ $# -gt 0 ]; do
  case "$1" in
    --apply)        APPLY=1 ;;
    --tz)           shift; TZ_TARGET="${1:-}" ;;
    --no-ipv6-off)  DO_IPV6=0 ;;
    --no-ntp-off)   DO_NTP=0 ;;
    --no-locale)    DO_LOCALE=0 ;;
    -h|--help)      sed -n '2,16p' "$0"; exit 0 ;;
    *) echo "未知参数: $1"; exit 64 ;;
  esac
  shift
done

OS="$(uname -s)"
echo "Claude 区域一致性设置 · $OS"
[ "$APPLY" -eq 1 ] && echo "模式：APPLY" || echo "模式：DRY-RUN（只打印）"
echo "────────────────────────────────────────────────────────"

# ---------- 1. 时区 ----------
if [ -z "$TZ_TARGET" ]; then
  GEO="$(curl -4 -s -m 8 'http://ip-api.com/json/?fields=timezone,country,city,query' 2>/dev/null)"
  TZ_TARGET="$(printf '%s' "$GEO" | sed -n 's/.*"timezone"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
  CITY="$(printf '%s' "$GEO" | sed -n 's/.*"city"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
  [ -n "$TZ_TARGET" ] && echo "按出口推断：$CITY -> $TZ_TARGET"
fi

if [ -z "$TZ_TARGET" ]; then
  echo "无法推断时区，请用 --tz 指定（如 --tz America/New_York）" >&2
  exit 64
fi

case "$TZ_TARGET" in
  Asia/Shanghai|Asia/Urumqi|Asia/Chongqing)
    echo "警告：你选的是中国大陆时区，若出口在海外会构成明显矛盾。" ;;
esac

echo "[计划] 时区 -> $TZ_TARGET"
[ "$DO_LOCALE" -eq 1 ] && echo "[计划] 区域格式 -> en_US，首选语言 -> en-US"
[ "$DO_NTP" -eq 1 ]    && echo "[计划] 关闭自动校时"
[ "$DO_IPV6" -eq 1 ]   && echo "[计划] 关闭 IPv6"

if [ "$APPLY" -eq 0 ]; then
  echo
  echo "DRY-RUN 结束。确认后加 --apply 执行。"
  exit 0
fi

echo
echo "执行中..."

# ---------- 2. 时区 ----------
if [ "$OS" = "Darwin" ]; then
  if sudo -n true 2>/dev/null; then
    sudo systemsetup -settimezone "$TZ_TARGET" && echo "[OK] 时区 = $(readlink /etc/localtime | sed 's|.*zoneinfo/||')"
    if [ "$DO_NTP" -eq 1 ]; then
      sudo systemsetup -setusingnetworktime off && echo "[OK] 已关闭自动校时"
    fi
  else
    echo "需要管理员权限，请执行："
    echo "  sudo systemsetup -settimezone $TZ_TARGET"
    [ "$DO_NTP" -eq 1 ] && echo "  sudo systemsetup -setusingnetworktime off"
  fi
else
  if command -v timedatectl >/dev/null 2>&1; then
    sudo timedatectl set-timezone "$TZ_TARGET" && echo "[OK] 时区 = $(timedatectl show -p Timezone --value)"
    [ "$DO_NTP" -eq 1 ] && sudo timedatectl set-ntp false && echo "[OK] 已关闭自动校时"
  else
    echo "未找到 timedatectl，请手工设置 /etc/timezone 与 /etc/localtime"
  fi
fi

# ---------- 3. 区域与语言（macOS） ----------
if [ "$DO_LOCALE" -eq 1 ] && [ "$OS" = "Darwin" ]; then
  defaults write -g AppleLocale -string "en_US"
  defaults write -g AppleLanguages -array "en-US" "en"
  echo "[OK] 区域 en_US，首选语言 en-US（需重新登录生效）"
fi

# ---------- 4. IPv6 ----------
if [ "$DO_IPV6" -eq 1 ]; then
  if [ "$OS" = "Darwin" ]; then
    for svc in $(networksetup -listallnetworkservices | tail -n +2); do
      networksetup -setv6off "$svc" 2>/dev/null && echo "[OK] 已关闭 IPv6: $svc"
    done
  else
    sudo sysctl -w net.ipv6.conf.all.disable_ipv6=1 >/dev/null 2>&1 \
      && echo "[OK] 已关闭 IPv6（临时，重启失效；持久化请写 /etc/sysctl.d/99-noipv6.conf）"
  fi
fi

# ---------- 5. DNS 缓存 ----------
if [ "$OS" = "Darwin" ]; then
  sudo dscacheutil -flushcache 2>/dev/null; sudo killall -HUP mDNSResponder 2>/dev/null
else
  sudo resolvectl flush-caches 2>/dev/null
fi
echo "[OK] 已清 DNS 缓存"

echo
echo "验收："
echo "  date; ls -l /etc/localtime"
echo "  curl -4 https://ipinfo.io/ip"
echo "  curl -s -m 4 https://api6.ipify.org   # 应为空"
echo "然后重启浏览器，打开 https://ip.net.coffee/claude/ 看「时区一致」与「语言」。"
