#!/bin/bash
# 对味 上线脚本：跑全部测试 → 通过才重启线上服务 → 轮询健康检查 → 打印「N 项全过 + 耗时」。
#
#   scripts/release.sh                跑测试 + 重启 launchd 服务 + 验证
#   scripts/release.sh --no-restart   只跑测试，不碰线上服务
#
# 环境变量（一般不用动）：TAO_PORT 线上端口(默认 8774) / TAO_LABEL launchd label(默认 com.ocean.tao)
#                         PYTHON 解释器(默认 /usr/bin/python3，与 start.sh 一致)
#
# 原生壳（~/Applications/对味.app）只是 WKWebView 开窗口加载 localhost，页面和 API 全由 server 提供，
# 所以重启 server 即可，壳不用重启（窗口里按 Cmd+R 刷新拿新页面）。
# 仅当 tao-shell.swift 有改动时才需要重跑 install.sh 重打壳——脚本会提示，但不自动做。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LABEL="${TAO_LABEL:-com.ocean.tao}"
PORT="${TAO_PORT:-8774}"
PYTHON="${PYTHON:-/usr/bin/python3}"
APP_BIN="$HOME/Applications/对味.app/Contents/MacOS/对味"

notify() {  # notify <标题> <正文>
    osascript -e "display notification \"$2\" with title \"$1\"" >/dev/null 2>&1 || true
}

fail() {    # fail <消息>：stderr 打印 + 通知 + exit 1
    echo "✗ $1" >&2
    notify "对味 上线失败" "$1"
    exit 1
}

run_tests() {  # 跑 tests/ 下全部测试；成功后设置 TEST_COUNT，失败 return 1
    local log; log="$(mktemp -t tao-release-tests)"
    if (cd "$ROOT" && "$PYTHON" -m unittest discover -s tests -p 'test_*.py' -v) >"$log" 2>&1; then
        tail -n 8 "$log"
        TEST_COUNT="$(sed -n 's/^Ran \([0-9][0-9]*\) test.*/\1/p' "$log" | tail -n 1)"
        rm -f "$log"
        return 0
    fi
    cat "$log" >&2
    rm -f "$log"
    return 1
}

verify_live() {  # verify_live <port> <秒>：轮询首页 + /health + /data，全通返回 0
    # 注意：先把响应收进变量再 grep——pipefail 下 `curl | grep -q` 会因 grep 提前退出让 curl 报 SIGPIPE 误判失败。
    local port="$1" budget="$2" i page health data
    local tries=$(( budget * 2 ))
    for (( i = 0; i < tries; i++ )); do
        page="$(curl -fsS --max-time 2 "http://127.0.0.1:$port/" 2>/dev/null || true)"
        health="$(curl -fsS --max-time 2 "http://127.0.0.1:$port/health" 2>/dev/null || true)"
        data="$(curl -fsS --max-time 2 "http://127.0.0.1:$port/data" 2>/dev/null || true)"
        if grep -qi '<html' <<<"$page" && grep -q '"ok": *true' <<<"$health" && grep -q '"recipes"' <<<"$data"; then
            return 0
        fi
        sleep 0.5
    done
    return 1
}

main() {
    local restart=1
    for arg in "$@"; do
        case "$arg" in
            --no-restart) restart=0 ;;
            -h|--help) sed -n '2,13p' "${BASH_SOURCE[0]}"; exit 0 ;;
            *) echo "未知参数: $arg（可用: --no-restart）" >&2; exit 2 ;;
        esac
    done

    SECONDS=0
    echo "▶ 跑测试（$ROOT/tests）"
    TEST_COUNT=0
    if ! run_tests; then
        echo "✗ 测试未通过，已中止，线上服务未重启（耗时 ${SECONDS}s）" >&2
        exit 1
    fi

    if (( restart == 0 )); then
        echo "✓ ${TEST_COUNT} 项全过（--no-restart，未重启线上服务），耗时 ${SECONDS}s"
        return 0
    fi

    echo "▶ 重启线上服务 $LABEL"
    launchctl kickstart -k "gui/$(id -u)/$LABEL" || fail "launchctl kickstart 失败（label=$LABEL）"
    if ! verify_live "$PORT" 10; then
        fail "重启后 10 秒内线上 :$PORT 没起来，看 ~/Library/Logs/tao.err.log"
    fi

    if [ -f "$ROOT/tao-shell.swift" ] && [ -f "$APP_BIN" ] && [ "$ROOT/tao-shell.swift" -nt "$APP_BIN" ]; then
        echo "ℹ tao-shell.swift 比已装的 对味.app 新：壳有改动，需要跑 bash $ROOT/install.sh 重打包（server 重启不会更新壳）"
    fi
    echo "✓ ${TEST_COUNT} 项全过，线上 :$PORT 已重启并通过健康检查，耗时 ${SECONDS}s"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
