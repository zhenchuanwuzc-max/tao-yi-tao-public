#!/bin/bash
# 对味 安装/接入脚本：配 launchd 自启 + 注册数据仓合并驱动 + 打 Dock .app。
# 两台机通用：代码 = 本脚本所在目录；数据 = ~/tao-yi-tao-data（缺失则尝试 clone）。
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LABEL="com.ocean.tao"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
DATA_DIR="$HOME/tao-yi-tao-data"
DATA_REPO="git@github.com:zhenchuanwuzc-max/tao-yi-tao-data.git"
PORT=8774
APP="$HOME/Applications/对味.app"
OLD_APP="$HOME/Applications/套一套.app"   # 改名前的旧 bundle，装完一并清掉（防 Dock 留孤儿）

echo "════════════════════════════════════"
echo "  对味 installer"
echo "  代码: $SCRIPT_DIR"
echo "  数据: $DATA_DIR"
echo "════════════════════════════════════"

# 1. 端口预检
if lsof -nP -iTCP:$PORT -sTCP:LISTEN >/dev/null 2>&1; then
    if launchctl list | grep -q "$LABEL"; then
        echo "✅ 端口 $PORT 被自己占用（重装场景）"
    else
        echo "⚠️  端口 $PORT 被别的进程占用，请先排查：lsof -i:$PORT"
    fi
fi

# 2. 数据仓：缺失则 clone（私有仓，需 SSH 权限）
if [ ! -d "$DATA_DIR/.git" ]; then
    if [ ! -d "$DATA_DIR" ] || [ -z "$(ls -A "$DATA_DIR" 2>/dev/null)" ]; then
        echo "📥 clone 数据仓 …"
        git clone "$DATA_REPO" "$DATA_DIR" 2>/dev/null || echo "  ⚠️ clone 失败（仓没建好 / 没权限）——先手动建库再重跑"
    fi
fi
# 注册合并驱动 + 跑一次同步（sync.sh 内部自愈注册 tao-union 驱动）
[ -f "$DATA_DIR/sync.sh" ] && /bin/bash "$DATA_DIR/sync.sh" >/dev/null 2>&1 || true

# 3. 生成 launchd plist（用 $HOME，不硬编码用户名）
mkdir -p "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"
cat > "$PLIST" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array><string>$SCRIPT_DIR/start.sh</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>
  <key>StandardOutPath</key><string>$HOME/Library/Logs/tao.out.log</string>
  <key>StandardErrorPath</key><string>$HOME/Library/Logs/tao.err.log</string>
  <key>EnvironmentVariables</key><dict>
    <key>TAO_PORT</key><string>$PORT</string>
    <key>TAO_DATA_DIR</key><string>$DATA_DIR</string>
    <key>LANG</key><string>en_US.UTF-8</string>
    <key>LC_ALL</key><string>en_US.UTF-8</string>
  </dict>
</dict></plist>
PL
launchctl unload "$PLIST" 2>/dev/null || true
launchctl load "$PLIST"
echo "✅ launchd 已加载（$LABEL，自启 + 崩溃自愈）"

# 4. Dock .app — 优先打「原生独立窗口」(Swift+WKWebView 壳)，无 swiftc/编译失败则回退浏览器壳(osacompile)。
#    幂等关键：全程在临时目录构建，整套成功后才 mv 替换旧 $APP；任一步失败就保留旧 app 不动，绝不"先删后建"。
LSREG="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"

# 4a. 构建原生壳到指定目录 $1；任一步失败 return 1（不碰旧 app）。localhost http 默认豁免 ATS，无需 Info.plist 例外。
build_swift_app() {
    # ⚠️ 必须分行：bash 同一 local 行声明多个变量时，右值在赋值前统一展开，
    #    `local dst=.. bin="$dst/.."` 里 bin 会拿到空的 $dst → 路径变成 /Contents/MacOS/...。
    local dst="$1"
    local bin="$dst/Contents/MacOS/对味"
    command -v swiftc >/dev/null 2>&1 || return 1
    mkdir -p "$dst/Contents/MacOS" "$dst/Contents/Resources" || return 1
    swiftc "$SCRIPT_DIR/tao-shell.swift" -o "$bin" 2>/dev/null || return 1   # 编译失败=换 fallback
    [ -x "$bin" ] || return 1
    [ -f "$SCRIPT_DIR/icon.icns" ] && cp "$SCRIPT_DIR/icon.icns" "$dst/Contents/Resources/对味.icns" || true
    cat > "$dst/Contents/Info.plist" <<PLIST || return 1
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>对味</string>
  <key>CFBundleDisplayName</key><string>对味</string>
  <key>CFBundleExecutable</key><string>对味</string>
  <key>CFBundleIdentifier</key><string>com.ocean.tao.shell</string>
  <key>CFBundleIconFile</key><string>对味</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSMinimumSystemVersion</key><string>11.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>TAO_PORT</key><string>$PORT</string>
</dict></plist>
PLIST
    codesign --force -s - "$dst" >/dev/null 2>&1 || true   # ad-hoc 本机自签；本地编译无 quarantine，Gatekeeper 不拦
    return 0
}

# 4b. fallback：osacompile 浏览器壳（双击调默认浏览器开 localhost）。同样构建到 $1。
build_osacompile_app() {
    local dst="$1"
    osacompile -o "$dst" -e "open location \"http://localhost:$PORT\"" 2>/dev/null || return 1
    if [ -f "$SCRIPT_DIR/icon.icns" ]; then
        cp "$SCRIPT_DIR/icon.icns" "$dst/Contents/Resources/applet.icns" 2>/dev/null || true
        /usr/libexec/PlistBuddy -c "Delete :CFBundleIconName" "$dst/Contents/Info.plist" 2>/dev/null || true
        rm -f "$dst/Contents/Resources/Assets.car" 2>/dev/null || true
        codesign --force -s - "$dst" >/dev/null 2>&1 || true
    fi
    return 0
}

TMP_APP="$(mktemp -d)/对味.app"
APP_KIND=""
if build_swift_app "$TMP_APP"; then
    APP_KIND="原生独立窗口"
else
    rm -rf "$TMP_APP" 2>/dev/null || true
    if build_osacompile_app "$TMP_APP"; then
        APP_KIND="浏览器壳(无 swiftc 回退)"
    fi
fi

if [ -n "$APP_KIND" ] && [ -d "$TMP_APP" ]; then
    rm -rf "$APP" 2>/dev/null || true        # 此刻新 app 已在临时目录就绪，才删旧的
    mkdir -p "$(dirname "$APP")"
    mv "$TMP_APP" "$APP"
    /usr/bin/touch "$APP" 2>/dev/null || true
    "$LSREG" -f "$APP" 2>/dev/null || true
    if [ "$OLD_APP" != "$APP" ] && [ -e "$OLD_APP" ]; then
        rm -rf "$OLD_APP" 2>/dev/null && echo "🧹 已删旧 bundle $OLD_APP（改名遗留）" || true
    fi
    echo "✅ 已打包 $APP（$APP_KIND，拖进 Dock 即可）"
else
    echo "⚠️ .app 打包失败（旧 app 已保留不动），可直接用浏览器开 http://localhost:$PORT"
fi

echo ""
echo "🎉 完成 → http://localhost:$PORT"
