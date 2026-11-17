#!/usr/bin/env python3
"""Claude 出口 IP 体检 · 跨平台，仅用标准库。

用法:
    python3 ipcheck.py            # 人类可读
    python3 ipcheck.py --json     # 机器可读
    python3 ipcheck.py --no-latency

检查:
    1. 默认出口 IPv4 (ipinfo.io)
    2. Cloudflare 看到的出口 IPv4 (cdn-cgi/trace)  -> 用于发现分流失效
    3. IPv6 出口是否可用                              -> 应为空
    4. ASN / ISP / hosting / proxy / mobile 标记
    5. IP 归属时区 vs 本机时区
    6. claude.ai / api.anthropic.com 延迟

退出码: 0 全部通过; 1 有告警; 2 有失败
"""

from __future__ import annotations

import json
import platform
import socket
import ssl
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime
from zoneinfo import ZoneInfo

TIMEOUT = 10
UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"

GREEN, YELLOW, RED, BOLD, DIM, RESET = (
    ("\033[32m", "\033[33m", "\033[31m", "\033[1m", "\033[2m", "\033[0m")
    if sys.stdout.isatty()
    else ("", "", "", "", "", "")
)


def fetch(url: str, timeout: int = TIMEOUT, ipv6: bool = False) -> str:
    """GET a URL and return text. ipv6=True forces AF_INET6 resolution."""
    req = urllib.request.Request(
        url, headers={"User-Agent": UA, "Accept": "application/json, text/plain, */*"}
    )
    ctx = ssl.create_default_context()

    if not ipv6:
        with urllib.request.urlopen(req, timeout=timeout, context=ctx) as r:
            return r.read().decode("utf-8", "replace")

    # Force IPv6: resolve AAAA only and connect to that address.
    host = urllib.parse.urlsplit(url).hostname
    infos = socket.getaddrinfo(host, 443, socket.AF_INET6, socket.SOCK_STREAM)
    if not infos:
        raise OSError("no AAAA record")
    addr = infos[0][4][0]
    conn = socket.create_connection((addr, 443), timeout=timeout)
    with ctx.wrap_socket(conn, server_hostname=host) as tls:
        path = urllib.parse.urlsplit(url).path or "/"
        tls.sendall(
            f"GET {path} HTTP/1.1\r\nHost: {host}\r\nUser-Agent: {UA}\r\n"
            f"Connection: close\r\n\r\n".encode()
        )
        chunks = []
        while True:
            b = tls.recv(4096)
            if not b:
                break
            chunks.append(b)
    raw = b"".join(chunks).decode("utf-8", "replace")
    return raw.split("\r\n\r\n", 1)[-1]


def timed(url: str) -> tuple[int, float]:
    start = time.time()
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT) as r:
            r.read(1)
            return r.status, (time.time() - start) * 1000
    except urllib.error.HTTPError as e:
        return e.code, (time.time() - start) * 1000
    except Exception:
        return 0, (time.time() - start) * 1000


def local_tz() -> str:
    try:
        return datetime.now().astimezone().tzinfo.tzname(None) or "?"
    except Exception:
        return "?"


def main() -> int:
    as_json = "--json" in sys.argv
    do_latency = "--no-latency" not in sys.argv

    rows: list[dict] = []

    def add(name: str, value: str, status: str) -> None:
        rows.append({"item": name, "value": value, "status": status})

    # 1) default IPv4 (ipinfo -> ipify 兜底)
    ip4 = country = city = region = org = ""
    try:
        data = json.loads(fetch("https://ipinfo.io/json"))
        ip4 = data.get("ip", "")
        city = data.get("city", "")
        region = data.get("region", "")
        country = data.get("country", "")
        org = data.get("org", "")
        add("出口 IPv4", f"{ip4}  {city}, {region} {country}  {org}", "ok")
    except Exception as e:  # noqa: BLE001
        try:
            ip4 = fetch("https://api.ipify.org").strip()
            add("出口 IPv4", f"{ip4}  （ipinfo 不可用: {e}）", "ok")
        except Exception as e2:  # noqa: BLE001
            add("出口 IPv4", f"获取失败: {e2}", "fail")

    # 2) Cloudflare view
    cf_ip = ""
    try:
        trace = fetch("https://www.cloudflare.com/cdn-cgi/trace")
        for line in trace.splitlines():
            if line.startswith("ip="):
                cf_ip = line.split("=", 1)[1].strip()
                break
        if cf_ip and ip4 and cf_ip != ip4:
            add("Cloudflare 出口", f"{cf_ip} ≠ {ip4}（分流失效或多出口）", "fail")
        else:
            add("Cloudflare 出口", f"{cf_ip or '?'}（与默认出口一致）", "ok")
    except Exception as e:  # noqa: BLE001
        add("Cloudflare 出口", f"获取失败: {e}", "warn")

    # 3) IPv6
    try:
        v6 = fetch("https://ipinfo.io/ip", ipv6=True).strip()
        add("IPv6 出口", f"{v6}（可用，可能绕过代理偷跑，建议关闭）", "warn")
    except Exception:
        add("IPv6 出口", "无（已禁用或无 IPv6 连通）", "ok")

    # 4) ASN / type
    ip_tz = ""
    try:
        q = "http://ip-api.com/json/?fields=status,country,regionName,city,isp,org,as,hosting,proxy,mobile,timezone"
        api = json.loads(fetch(q))
        if api.get("status") == "success":
            kind = "移动网络" if api.get("mobile") else ("机房/IDC" if api.get("hosting") else "住宅/ISP")
            ip_tz = api.get("timezone", "") or ""
            flagged = api.get("proxy")
            add(
                "IP 属性",
                f"{kind}  ASN {api.get('as', '?')}  ISP {api.get('isp', '?')}"
                + ("  ← 被标记 proxy/vpn" if flagged else ""),
                "warn" if flagged else "ok",
            )
        else:
            add("IP 属性", "ip-api 返回失败", "warn")
    except Exception as e:  # noqa: BLE001
        add("IP 属性", f"查询失败: {e}", "warn")

    # 5) timezone consistency
    sys_tz = local_tz()
    try:
        sys_iana = datetime.now().astimezone().tzinfo
        # best-effort IANA name
        name = getattr(sys_iana, "key", None) or getattr(sys_iana, "zone", None) or ""
        if not name:
            import os, re  # noqa: E401
            link = ""
            try:
                link = os.path.realpath("/etc/localtime")
            except Exception:
                pass
            m = re.search(r"zoneinfo/(.+)$", link)
            name = m.group(1) if m else sys_tz
    except Exception:
        name = sys_tz

    if name in ("Asia/Shanghai", "Asia/Urumqi", "Asia/Chongqing", "PRC"):
        add("系统时区", f"{name} ← 中国大陆时区，Claude Code 直接读这个", "fail")
    elif ip_tz and name and ip_tz != name:
        add("时区一致性", f"IP 时区 {ip_tz} ≠ 系统 {name}", "warn")
    elif ip_tz:
        add("时区一致性", f"一致（{ip_tz}）", "ok")
    else:
        add("系统时区", name or "?", "ok" if name else "warn")

    # 6) latency
    if do_latency:
        for url in ("https://claude.ai/", "https://api.anthropic.com/"):
            code, ms = timed(url)
            host = url.replace("https://", "").rstrip("/")
            if code == 0:
                add(host, "连接失败（超时/重置）", "fail")
            elif code >= 500:
                add(host, f"HTTP {code}  {ms:.0f} ms", "warn")
            else:
                add(host, f"HTTP {code}  {ms:.0f} ms", "ok")

    # ---- output ----
    if as_json:
        print(json.dumps({
            "generated_at": datetime.now().isoformat(timespec="seconds"),
            "platform": platform.platform(),
            "rows": rows,
            "summary": {
                "ok": sum(r["status"] == "ok" for r in rows),
                "warn": sum(r["status"] == "warn" for r in rows),
                "fail": sum(r["status"] == "fail" for r in rows),
            },
        }, ensure_ascii=False, indent=2))
    else:
        print(f"{BOLD}Claude 出口 IP 体检{RESET}  ·  {datetime.now():%Y-%m-%d %H:%M}  ·  {platform.system()}")
        print("─" * 72)
        mark = {"ok": f"{GREEN}[✅]{RESET}", "warn": f"{YELLOW}[⚠️ ]{RESET}", "fail": f"{RED}[❌]{RESET}"}
        for r in rows:
            print(f"{mark[r['status']]} {r['item']:<14} {r['value']}")
        print("─" * 72)
        ok = sum(r["status"] == "ok" for r in rows)
        warn = sum(r["status"] == "warn" for r in rows)
        fail = sum(r["status"] == "fail" for r in rows)
        total = len(rows)
        if fail == 0 and warn == 0:
            print(f"{GREEN}结论：{ok}/{total} 全部通过{RESET}")
        elif fail == 0:
            print(f"{YELLOW}结论：{ok} 通过 / {warn} 告警 / 0 失败{RESET}")
        else:
            print(f"{RED}结论：{ok} 通过 / {warn} 告警 / {fail} 失败 ← 先修失败项{RESET}")
        print(f"{DIM}浏览器侧还需确认 WebRTC / Canvas / 时区指纹 → https://ip.net.coffee/claude/{RESET}")

    fail = sum(r["status"] == "fail" for r in rows)
    warn = sum(r["status"] == "warn" for r in rows)
    return 2 if fail else (1 if warn else 0)


if __name__ == "__main__":
    sys.exit(main())
