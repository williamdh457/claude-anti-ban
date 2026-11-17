#!/usr/bin/env bash
# Claude 环境自检 · macOS / Linux
# 用法：
#   bash check_env.sh            # 全量自检
#   bash check_env.sh --dns      # 额外做 DNS 出口查询
#   bash check_env.sh --quiet    # 只输出结论
#
# 依赖：curl；可选 dig / scutil / resolvectl / timedatectl
# 退出码：0 = 全部通过；1 = 有告警；2 = 有失败

set -uo pipefail

QUIET=0
DO_DNS=0
for arg in "$@"; do
  case "$arg" in
    --quiet) QUIET=1 ;;
    --dns)   DO_DNS=1 ;;
    -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
  esac
done

if [ -t 1 ] && [ "$QUIET" -eq 0 ]; then
  G=$'\033[32m'; Y=$'\033[33m'; R=$'\033[31m'; B=$'\033[1m'; N=$'\033[0m'
else
  G=""; Y=""; R=""; B=""; N=""
fi

PASS=0; WARN=0; FAIL=0
ok()   { PASS=$((PASS+1)); [ "$QUIET" -eq 0 ] && printf '%s[✅]%s %s\t%s\n' "$G" "$N" "$1" "$2"; }
warn() { WARN=$((WARN+1)); [ "$QUIET" -eq 0 ] && printf '%s[⚠️ ]%s %s\t%s\n' "$Y" "$N" "$1" "$2"; }
bad()  { FAIL=$((FAIL+1)); [ "$QUIET" -eq 0 ] && printf '%s[❌]%s %s\t%s\n' "$R" "$N" "$1" "$2"; }
line() { [ "$QUIET" -eq 0 ] && printf '%s\n' "────────────────────────────────────────────────────────"; }

have() { command -v "$1" >/dev/null 2>&1; }

OS="$(uname -s)"
line
printf '%sClaude 环境自检%s  ·  %s  ·  %s\n' "$B" "$N" "$(date '+%Y-%m-%d %H:%M')" "$OS"
line

# ---------- 1. 时区 ----------
TZ_NAME=""
if [ "$OS" = "Darwin" ]; then
  TZ_NAME="$(readlink /etc/localtime 2>/dev/null | sed 's|.*zoneinfo/||')"
  [ -z "$TZ_NAME" ] && TZ_NAME="$(defaults read -g AppleLocale 2>/dev/null || true)"
else
  if have timedatectl; then
    TZ_NAME="$(timedatectl show -p Timezone --value 2>/dev/null)"
  fi
  [ -z "$TZ_NAME" ] && [ -f /etc/timezone ] && TZ_NAME="$(cat /etc/timezone)"
fi
[ -z "$TZ_NAME" ] && TZ_NAME="$(date +%Z)"

case "$TZ_NAME" in
  Asia/Shanghai|Asia/Urumqi|Asia/Chongqing|PRC|CST-8)
    bad "系统时区" "$TZ_NAME  ← 中国大陆时区，Claude Code 直接读这个" ;;
  "")
    warn "系统时区" "读取失败，请手工确认" ;;
  *)
    ok "系统时区" "$TZ_NAME" ;;
esac

# ---------- 2. 语言 ----------
LANGV=""
if [ "$OS" = "Darwin" ]; then
  LANGV="$(defaults read -g AppleLocale 2>/dev/null)"
  [ -z "$LANGV" ] && LANGV="${LANG:-}"
else
  LANGV="$(locale 2>/dev/null | awk -F= '/^LANG=/{print $2}' | tr -d '"')"
fi
case "$LANGV" in
  *zh_CN*|*zh-CN*) warn "系统语言" "$LANGV  ← 建议改 en_US（界面语言可保留中文）" ;;
  "")              warn "系统语言" "读取失败" ;;
  *)               ok   "系统语言" "$LANGV" ;;
esac

# ---------- 3. IPv6 ----------
V6="$(curl -s -m 4 https://api6.ipify.org 2>/dev/null | tr -d '\n')"
if [ -n "$V6" ]; then
  warn "IPv6 出口" "$V6  ← IPv6 可用，可能绕过代理偷跑，建议关闭"
else
  ok "IPv6 出口" "无（已禁用或无 IPv6 连通）"
fi

# ---------- 4. DNS 服务器 ----------
DNSLIST=""
if [ "$OS" = "Darwin" ]; then
  DNSLIST="$(scutil --dns 2>/dev/null | awk '/nameserver\[[0-9]+\]/{print $3}' | sort -u | head -4 | paste -sd ', ' -)"
else
  if have resolvectl; then
    DNSLIST="$(resolvectl status 2>/dev/null | awk '/Current DNS Server/{print $4}' | sort -u | paste -sd ', ' -)"
  fi
  [ -z "$DNSLIST" ] && DNSLIST="$(awk '/^nameserver/{print $2}' /etc/resolv.conf 2>/dev/null | paste -sd ', ' -)"
fi
[ -z "$DNSLIST" ] && DNSLIST="未知"
if printf '%s' "$DNSLIST" | grep -qE '192\.168\.|10\.|172\.(1[6-9]|2[0-9]|3[01])\.|127\.0\.0\.1'; then
  warn "DNS 服务器" "$DNSLIST  ← 本地/路由器 DNS，注意是否走代理"
else
  ok "DNS 服务器" "$DNSLIST"
fi

# ---------- 5. 出口 IP ----------
IPJSON="$(curl -4 -s -m 10 https://ipinfo.io/json 2>/dev/null)"
if [ -z "$IPJSON" ]; then
  bad "出口 IPv4" "无法获取（网络不通？）"
  IP4=""; COUNTRY=""; CITY=""; ORG=""
else
  IP4="$(printf '%s' "$IPJSON" | sed -n 's/.*"ip"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
  CITY="$(printf '%s' "$IPJSON" | sed -n 's/.*"city"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
  REGION="$(printf '%s' "$IPJSON" | sed -n 's/.*"region"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
  COUNTRY="$(printf '%s' "$IPJSON" | sed -n 's/.*"country"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
  ORG="$(printf '%s' "$IPJSON" | sed -n 's/.*"org"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
  ok "出口 IPv4" "${IP4:-?}  ${CITY:-}, ${REGION:-} ${COUNTRY:-}  ${ORG:-}"
fi

# ---------- 6. Cloudflare 出口（用于发现分流失效）----------
CFIP="$(curl -4 -s -m 10 https://www.cloudflare.com/cdn-cgi/trace 2>/dev/null | awk -F= '/^ip=/{print $2}')"
if [ -z "$CFIP" ]; then
  warn "Cloudflare 出口" "无法获取"
elif [ -n "$IP4" ] && [ "$CFIP" != "$IP4" ]; then
  bad "Cloudflare 出口" "$CFIP ≠ 默认出口 $IP4  ← 分流失效或多出口"
else
  ok "Cloudflare 出口" "${CFIP}（与默认出口一致）"
fi

# ---------- 7. ASN / 属性 ----------
APIJSON="$(curl -4 -s -m 10 "http://ip-api.com/json/?fields=status,country,regionName,city,isp,org,as,hosting,proxy,mobile,timezone" 2>/dev/null)"
if [ -n "$APIJSON" ] && printf '%s' "$APIJSON" | grep -q '"status":"success"'; then
  HOSTING="$(printf '%s' "$APIJSON" | grep -o '"hosting":[a-z]*' | cut -d: -f2)"
  PROXY="$(printf '%s' "$APIJSON" | grep -o '"proxy":[a-z]*' | cut -d: -f2)"
  MOBILE="$(printf '%s' "$APIJSON" | grep -o '"mobile":[a-z]*' | cut -d: -f2)"
  ASN="$(printf '%s' "$APIJSON" | sed -n 's/.*"as"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
  IPTZ="$(printf '%s' "$APIJSON" | sed -n 's/.*"timezone"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
  TYPE="住宅/ISP"
  [ "$HOSTING" = "true" ] && TYPE="机房/IDC"
  [ "$MOBILE"  = "true" ] && TYPE="移动网络"
  if [ "$PROXY" = "true" ]; then
    warn "IP 属性" "${TYPE}（ASN ${ASN}）← 被标记为 proxy/vpn"
  else
    ok "IP 属性" "${TYPE}（ASN ${ASN}）"
  fi
  # 时区一致性
  if [ -n "$IPTZ" ] && [ -n "$TZ_NAME" ] && [ "$IPTZ" != "$TZ_NAME" ]; then
    warn "时区一致性" "IP 时区 $IPTZ ≠ 系统 $TZ_NAME"
  elif [ -n "$IPTZ" ]; then
    ok "时区一致性" "IP 时区 = 系统时区（${IPTZ}）"
  fi
else
  warn "IP 属性" "ip-api 查询失败（可能被限流）"
fi

# ---------- 8. Claude 连通性 ----------
for host in https://claude.ai/ https://api.anthropic.com/; do
  read -r code t < <(curl -4 -o /dev/null -s -m 15 -w "%{http_code} %{time_total}" "$host" 2>/dev/null)
  ms=$(awk -v t="${t:-0}" 'BEGIN{printf "%d", t*1000}')
  name="$(printf '%s' "$host" | sed 's|https://||; s|/$||')"
  if [ "${code:-0}" = "000" ]; then
    bad "$name" "连接失败（超时/被重置）"
  elif [ "${code:-0}" -ge 500 ]; then
    warn "$name" "HTTP $code  ${ms}ms"
  else
    ok "$name" "HTTP $code  ${ms}ms"
  fi
done

# ---------- 9. 系统代理 ----------
if [ "$OS" = "Darwin" ]; then
  PROXYINFO="$(scutil --proxy 2>/dev/null | awk '/HTTPEnable|HTTPSEnable|SOCKSEnable/{print}' | paste -sd ' ' -)"
  if printf '%s' "$PROXYINFO" | grep -q ': 1'; then ok "系统代理" "已启用"; else warn "系统代理" "未启用（若用 TUN 模式可忽略）"; fi
else
  if [ -n "${http_proxy:-}${https_proxy:-}${HTTP_PROXY:-}" ]; then ok "系统代理" "环境变量已设置"; else warn "系统代理" "未设置（若用 TUN 模式可忽略）"; fi
fi

# ---------- 10. 可选 DNS 出口 ----------
if [ "$DO_DNS" -eq 1 ]; then
  if have dig; then
    D="$(dig +short +time=3 +tries=1 TXT whoami.ds.akahelp.net 2>/dev/null | tr -d '"' | awk '{print $NF}' | head -1)"
    if [ -n "$D" ]; then
      if [ -n "$IP4" ] && [ "$D" = "$IP4" ]; then
        ok "DNS 出口" "${D}（= 代理出口）"
      else
        bad "DNS 出口" "$D ≠ 出口 $IP4  ← DNS 泄露"
      fi
    else
      warn "DNS 出口" "查询失败（无 dig 或网络限制）"
    fi
  else
    warn "DNS 出口" "未安装 dig，跳过（用 https://ip.net.coffee/dns/ 检测）"
  fi
fi

line
TOTAL=$((PASS+WARN+FAIL))
if [ "$FAIL" -eq 0 ] && [ "$WARN" -eq 0 ]; then
  printf '%s结论：%d/%d 全部通过%s\n' "$G" "$PASS" "$TOTAL" "$N"
  RC=0
elif [ "$FAIL" -eq 0 ]; then
  printf '%s结论：%d 通过 / %d 告警 / 0 失败%s\n' "$Y" "$PASS" "$WARN" "$N"
  RC=1
else
  printf '%s结论：%d 通过 / %d 告警 / %d 失败  ← 先修失败项再打开 Claude%s\n' "$R" "$PASS" "$WARN" "$FAIL" "$N"
  RC=2
fi
[ "$QUIET" -eq 0 ] && printf '%s\n' "浏览器侧还需确认 WebRTC / Canvas / 时区指纹 → https://ip.net.coffee/claude/"
exit $RC
