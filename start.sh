#!/bin/bash
# 对味 启动脚本（被 launchd 调用）。代码在 ~/tao-yi-tao/，数据在 ~/tao-yi-tao-data/。
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
DATA_DIR="${TAO_DATA_DIR:-$HOME/tao-yi-tao-data}"
# 启动时后台跑一次 git 同步（自带 rebase + union 合并；放后台绝不拖死 server 启动）
SYNC_SH="$DATA_DIR/sync.sh"
if [ -f "$SYNC_SH" ]; then
    /bin/bash "$SYNC_SH" >> "$HOME/Library/Logs/tao-sync.log" 2>&1 &
fi
exec /usr/bin/python3 "$SCRIPT_DIR/server.py"
