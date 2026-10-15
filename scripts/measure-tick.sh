#!/usr/bin/env bash
# 采集 Vitals 主线程采样耗时基线，用于优化前后同口径对比。
#
# 口径固定：同一 interval（1s）、直接启动被测 bundle 内的二进制、只收该 PID 的日志，
# 因此不会和用户自己开着的 Vitals 实例混在一起。
#
# 用法: scripts/measure-tick.sh [持续秒数=30]
set -euo pipefail

DURATION="${1:-30}"
APP="${APP_PATH:-.ci-dd/Build/Products/Debug/Vitals.app}"
SUBSYSTEM="com.cookabc.vitals"

if [[ ! -d "$APP" ]]; then
    echo "未找到 $APP；先构建：xcodebuild -project Vitals.xcodeproj -scheme Vitals -destination 'platform=macOS' -derivedDataPath .ci-dd build"
    exit 1
fi

BIN="$APP/Contents/MacOS/Vitals"

# -samplingInterval/-showProcesses 走 NSUserDefaults 的 argument domain，优先级最高，
# 保证测量条件不受本机已存偏好影响。
"$BIN" --debug-panel -samplingInterval 1 -showProcesses YES >/dev/null 2>&1 &
PID=$!
cleanup() { kill "$PID" 2>/dev/null || true; wait "$PID" 2>/dev/null || true; }
trap cleanup EXIT

echo "采集 ${DURATION}s，pid=$PID，app=$APP"
sleep "$DURATION"
cleanup
trap - EXIT

LINES="$(log show --last "${DURATION}s" \
    --predicate "subsystem == \"$SUBSYSTEM\" AND processID == $PID" \
    --info --style compact 2>/dev/null | grep 'tick total_us=' || true)"

if [[ -z "$LINES" ]]; then
    echo "未取到 tick 日志。确认以 Debug 构建（指标行在 #if DEBUG 内），且 unified log 未被限速。"
    exit 1
fi

metric() {
    local label="$1" pattern="$2"
    local nums n
    nums="$(printf '%s\n' "$LINES" | sed -n "s/.*${pattern}=\([0-9]*\).*/\1/p" | sort -n)"
    n="$(printf '%s\n' "$nums" | grep -c '[0-9]' || true)"
    if [[ "$n" -eq 0 ]]; then
        printf '%-10s n=0   (本窗口无样本)\n' "$label"
        return
    fi
    printf '%s\n' "$nums" | awk -v l="$label" -v n="$n" '
        { a[NR] = $1 }
        END {
            i50 = int(0.5 * n + 0.5); if (i50 < 1) i50 = 1
            i95 = int(0.95 * n + 0.5); if (i95 > n) i95 = n; if (i95 < 1) i95 = 1
            printf "%-10s n=%-4d p50=%-9d p95=%-9d max=%d  (us)\n", l, n, a[i50], a[i95], a[n]
        }'
}

echo
echo "=== Vitals tick 耗时基线 (${DURATION}s, interval=1s) ==="
metric "total_us" "total_us"
metric "off_us" "off_us"
metric "main_us" "main_us"
echo
echo "total_us = 一次 tick 的墙钟跨度（含让给后台的等待）"
echo "off_us   = 其中 await 后台采样队列的时间：进程枚举/逐进程 rusage + IOKit GPU 计数"
echo "main_us  = total_us - off_us，主线程真正被占用的时长，与优化前的 total_us 同口径可比"
