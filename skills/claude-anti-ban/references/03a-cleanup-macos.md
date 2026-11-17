# 03a · 痕迹清理 · macOS

> 原则：**先审计、再备份、最后才删；删除一律进废纸篓，不用 `rm -rf`。**
> 目标不是「删光」，而是「把属于旧账号的那部分身份状态移走，同时不碰你的项目和历史」。
> 参考实现：`Pluviobyte/claude-ban-clean`、`suyuan2022/suyuan-skill`（claude-cleanup），本文件在其基础上补全浏览器与设备记录部分。

---

## 一、审计（只读，不删任何东西）

```bash
# 1) 系统身份面
sw_vers                                   # 系统版本
readlink /etc/localtime | sed 's|.*zoneinfo/||'   # 时区
defaults read -g AppleLocale              # 区域/语言
networksetup -getinfo "Wi-Fi" | head -6   # IPv6 状态

# 2) Claude Code / Desktop 数据体积
du -sh ~/.claude ~/.claude.json ~/.config/claude ~/.cache/claude 2>/dev/null
du -sh ~/Library/Application\ Support/Claude 2>/dev/null
du -sh ~/Library/Caches/com.anthropic.claudefordesktop* 2>/dev/null
du -sh ~/Library/Logs/Claude 2>/dev/null

# 3) 钥匙串条目（只查存在性，不读取值）
security find-generic-password -s "Claude Code-credentials" >/dev/null 2>&1 \
  && echo "存在 Claude Code-credentials" || echo "无"

# 4) 浏览器 Profile 数量
ls ~/Library/Application\ Support/Google/Chrome/ | grep -c '^Profile\|^Default'

# 5) VSCode 扩展
ls ~/.vscode/extensions 2>/dev/null | grep -i anthropic
```

审计输出应该能回答：**这台机器上有几个 Claude 账号的痕迹、在哪些位置、各占多少空间。**

---

## 二、保护清单（绝对不动）

```
~/.claude/projects/            # 项目会话记录
~/.claude/sessions/
~/.claude/history.jsonl
~/.claude/file-history/
~/.claude/skills/  plugins/  hooks/  commands/  agents/  mcp-servers/
~/.claude/CLAUDE.md
~/.claude/settings.json  settings.local.json
~/.claude/backups/
任何项目目录、Git 仓库
浏览器书签、历史、密码、其他站点数据
```

删之前先确认目标不在这个清单里，重叠就停。

---

## 三、备份

```bash
STAMP=$(date +%Y%m%d-%H%M%S)
BK="$HOME/ClaudeBackups/$STAMP"
mkdir -p "$BK" && chmod 700 "$BK"

# 全量复制要动的目录
rsync -a ~/.claude/ "$BK/dot-claude/" 2>/dev/null
cp -p ~/.claude.json "$BK/" 2>/dev/null
rsync -a "$HOME/Library/Application Support/Claude/" "$BK/app-support-Claude/" 2>/dev/null

# 逐文件校验
cd "$BK" && find . -type f -exec shasum -a 256 {} \; > MANIFEST.sha256
wc -l MANIFEST.sha256
```

> 备份目录权限 700，别提交到 GitHub，别放进云同步盘。备份里可能含 token。

---

## 四、分层清理

### 4.1 可再生缓存（安全，直接清）

```bash
TRASH="$HOME/.Trash/ClaudeCleanup-$STAMP"
mkdir -p "$TRASH"

for p in \
  "$HOME/.claude/cache" \
  "$HOME/.claude/stats-cache.json" \
  "$HOME/.claude/telemetry" \
  "$HOME/.claude/usage.jsonl" \
  "$HOME/.claude/usage.with-fix.jsonl" \
  "$HOME/Library/Caches/claude-cli-nodejs" \
  "$HOME/Library/Logs/Claude" \
  "$HOME/Library/Logs/DiagnosticReports/Claude"* \
  "$HOME/Library/Application Support/CrashReporter/Claude"* ; do
  [ -e "$p" ] && mv "$p" "$TRASH/" && echo "moved: $p"
done
```

> 用 `mv` 到 `~/.Trash`，不用 `rm`。真删错了还能捞回来。

### 4.2 桌面端登录态与数据

```bash
# 先正常退出 App（不要 kill）
osascript -e 'quit app "Claude"' 2>/dev/null
sleep 2
pgrep -fl "Claude" | grep -v grep && echo "还有进程，先处理"

# 再移走数据目录
mv "$HOME/Library/Application Support/Claude" "$TRASH/AppSupport-Claude"
mv "$HOME/Library/Preferences/com.anthropic.claudefordesktop.plist" "$TRASH/" 2>/dev/null
mv "$HOME/Library/Caches/com.anthropic.claudefordesktop"* "$TRASH/" 2>/dev/null
```

> `Application Support/Claude` 里不只有登录态，还有 Code 标签页的会话列表、`scratch-workspaces` 里写过的文件、Cowork 会话、虚拟机镜像。**移走之前确认这些你不需要。**

### 4.3 Claude Code 凭据与账号字段

```bash
# 退出登录（推荐用官方命令，而不是删文件）
claude logout 2>/dev/null || true

# 删钥匙串条目（会退出 CLI 登录）
security delete-generic-password -s "Claude Code-credentials" 2>/dev/null \
  && echo "已删钥匙串条目"

# 账号字段（只改白名单字段，不要整文件删）
python3 - <<'PY'
import json, os, secrets, pathlib
p = pathlib.Path.home()/".claude.json"
if not p.exists():
    raise SystemExit("no ~/.claude.json")
d = json.loads(p.read_text())
changed = []
for k in ("userID", "machineID"):
    if k in d:
        d[k] = secrets.token_hex(32)
        changed.append(k)
# 已知账号缓存字段
for k in ("oauthAccount", "accountUuid", "organizationUuid"):
    if k in d:
        d.pop(k); changed.append(k+"(removed)")
p.write_text(json.dumps(d, ensure_ascii=False, indent=2))
print("changed:", changed)
PY
```

> 只动这几个键。`projects`、`mcpServers`、`settings` 一律保留。
> 改 `userID` / `machineID` 只是换本地标识，**不代表平台侧的关联判断会变**——别指望它解决封号。

### 4.4 设备记录（单独授权才做）

```bash
# 这两个是 Anthropic 的设备标识文件
ls -la ~/.claude/ant-did ~/.claude/ant-device-registry.json 2>/dev/null

# 确认要删再删（进废纸篓）
mv ~/.claude/ant-did "$TRASH/" 2>/dev/null
mv ~/.claude/ant-device-registry.json "$TRASH/" 2>/dev/null
```

> 这不是「重置底层密钥」，只是移走设备登记文件。删了之后客户端会重新生成——新 ID，但同一台硬件。

### 4.5 浏览器（Chrome / Safari）

**优先用浏览器自带的站点数据管理**（最安全）：

```
Chrome → 设置 → 隐私和安全 → 第三方 Cookie → 查看所有站点数据
→ 搜索 anthropic / claude → 逐个删除
```

要清的四类：Cookies、Local Storage、IndexedDB、Service Worker / Cache Storage。
另外检查：站点权限里的**地理位置**授权（授权过 = 强标识）。

命令行方式（Chrome 已完全退出后）：

```bash
PROFILE="$HOME/Library/Application Support/Google/Chrome/Default"
TRASH_B="$TRASH/chrome-Default"
mkdir -p "$TRASH_B"

# 站点数据目录（按域名命名）
for d in "Local Storage/leveldb" "IndexedDB" "Service Worker/CacheStorage" "Session Storage"; do
  find "$PROFILE/$d" -maxdepth 2 -iname "*claude*" -o -maxdepth 2 -iname "*anthropic*" 2>/dev/null
done

# Cookie 库：先备份，再按 host_key 精确删除
cp "$PROFILE/Cookies" "$TRASH_B/Cookies.bak"
sqlite3 "$PROFILE/Cookies" \
  "DELETE FROM cookies WHERE host_key LIKE '%claude.ai%'
     OR host_key LIKE '%anthropic.com%'
     OR host_key LIKE '%claude.com%'
     OR host_key LIKE '%withpersona.com%';"
sqlite3 "$PROFILE/Cookies" "SELECT COUNT(*) FROM cookies;"
```

**注意**：

- 不要用「文件名包含 claude 就整目录删」——会误删 GitHub 仓库、书签、其他应用记录；
- LevelDB（Local Storage / IndexedDB）不要用文本搜索后整库删，会破坏整个 Profile；用浏览器设置界面删最稳；
- `withpersona.com`、Cloudflare、hCaptcha 是共享域，**按顶层站点判断**，别把 ChatGPT / 其他站的同域数据一起删了；
- 多个 Profile 要逐个检查（`Default`、`Profile 1`、`Profile 2`…）。

Safari：

```bash
# 只能整体清站点数据，粒度较粗；建议用 GUI
# Safari → 设置 → 隐私 → 管理网站数据 → 搜索 claude → 移除
```

### 4.6 编辑器

```bash
mv ~/.vscode/extensions/anthropic.* "$TRASH/" 2>/dev/null
mv "$HOME/Library/Application Support/Code/User/globalStorage/anthropic."* "$TRASH/" 2>/dev/null
```

### 4.7 系统层

```bash
sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder   # DNS 缓存
grep -n -i "claude\|anthropic" /etc/hosts                        # 检查 hosts 残留
networksetup -listallnetworkservices                            # 检查代理残留
pbcopy < /dev/null                                              # 清剪贴板
```

---

## 五、验收

```bash
# 1) 目标路径应已不存在
ls ~/.claude/cache ~/Library/Logs/Claude 2>&1 | head

# 2) 保护路径应完好
ls ~/.claude/projects ~/.claude/settings.json 2>&1

# 3) Cookie 里不应再有 claude 域
sqlite3 "$HOME/Library/Application Support/Google/Chrome/Default/Cookies" \
  "SELECT host_key FROM cookies WHERE host_key LIKE '%claude%' OR host_key LIKE '%anthropic%';"

# 4) 钥匙串
security find-generic-password -s "Claude Code-credentials" 2>&1 | head -1

# 5) 备份可读
ls -la "$HOME/ClaudeBackups/$STAMP" && head -3 "$HOME/ClaudeBackups/$STAMP/MANIFEST.sha256"
```

报告里要写清：**删了什么、备份在哪、哪些没删掉（及原因）、怎么恢复。**

---

## 六、回滚

```bash
# 从备份恢复
rsync -a "$HOME/ClaudeBackups/$STAMP/dot-claude/" ~/.claude/
cp -p "$HOME/ClaudeBackups/$STAMP/.claude.json" ~/.claude.json

# 从废纸篓捞回
open ~/.Trash/ClaudeCleanup-$STAMP
```

---

## 七、清不掉的东西（必须靠「换」）

| 标识 | 说明 |
|---|---|
| 支付卡 BIN / 卡号 | 服务端记录 |
| 手机号 / 邮箱 | 一次性绑定，永久记录 |
| 硬件指纹 | 机型、序列号、GPU、屏幕、字体列表 |
| ISP 分配记录 | 运营商侧 |
| 服务端风控历史 | 你无法访问 |
| 已建立的账号关联 | 同 Profile 多号、同卡多号，已上传 |

**所以换号 = 换一整套身份要素**，不是删几个目录。

---

## 八、常见错误

| 错误 | 后果 | 正确做法 |
|---|---|---|
| `rm -rf ~/.claude` | 项目会话、skills、hooks 全没 | 只移 cache/logs，其余按白名单 |
| 用 `kill -9` 结束 Claude | 数据库可能损坏 | `osascript -e 'quit app "Claude"'` |
| 删整个 `Application Support/Claude` | Code 会话、scratch 文件一起没 | 先确认，再移走 |
| 文本搜索 LevelDB 后整库删 | Profile 损坏，全部站点掉登录 | 用浏览器设置界面删站点数据 |
| 删共享域（withpersona / cloudflare） | 其他站点也掉登录 | 按顶层站点判断 |
| 备份放在 iCloud / Git | token 泄露 | 放本地、权限 700 |
| 以为清完就「无痕」 | 硬件与支付层仍在 | 换身份要素 |
