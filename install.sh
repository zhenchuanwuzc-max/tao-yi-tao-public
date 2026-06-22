#!/bin/bash
# 套一套 安装/接入脚本：配 launchd 自启 + 注册数据仓合并驱动 + 打 Dock .app。
# 两台机通用：代码 = 本脚本所在目录；数据 = ~/tao-yi-tao-data（缺失则尝试 clone）。
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LABEL="com.ocean.tao"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
DATA_DIR="$HOME/tao-yi-tao-data"
DATA_REPO="git@github.com:zhenchuanwuzc-max/tao-yi-tao-data.git"
PORT=8774
APP="$HOME/Applications/套一套.app"

echo "════════════════════════════════════"
echo "  套一套 installer"
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

# 4. Dock .app（极简：打开 localhost）+ 套自定义图标
rm -rf "$APP"
if osacompile -o "$APP" -e "open location \"http://localhost:$PORT\"" 2>/dev/null; then
    # osacompile 打出来默认是灰色 applet 图标；用仓里的 icon.icns 覆盖（cosmetic，失败不阻断安装）
    ICNS="$SCRIPT_DIR/icon.icns"
    if [ -f "$ICNS" ]; then
        cp "$ICNS" "$APP/Contents/Resources/applet.icns" 2>/dev/null || true
        # 删掉 asset-catalog 图标源，让 applet.icns 成唯一图标源（否则 Dock 仍认 Assets.car 默认图标）
        /usr/libexec/PlistBuddy -c "Delete :CFBundleIconName" "$APP/Contents/Info.plist" 2>/dev/null || true
        rm -f "$APP/Contents/Resources/Assets.car" 2>/dev/null || true
        codesign --force -s - "$APP" >/dev/null 2>&1 || true   # 包已改，重签名
        /usr/bin/touch "$APP" 2>/dev/null || true
        LSREG="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"
        "$LSREG" -f "$APP" 2>/dev/null || true
    fi
    echo "✅ 已打包 $APP（拖进 Dock 即可）"
else
    echo "⚠️ .app 打包失败，可直接用浏览器开 http://localhost:$PORT"
fi

echo ""
echo "🎉 完成 → http://localhost:$PORT"
