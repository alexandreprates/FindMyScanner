#!/usr/bin/env bash

[ -z "$1" ] && { echo "Usage: $0 <environment>"; exit 1; }

if command -v pio >/dev/null 2>&1; then
    PLATFORMIO_BIN="pio"
elif command -v platformio >/dev/null 2>&1; then
    PLATFORMIO_BIN="platformio"
else
    echo "PlatformIO command not found. Please install PlatformIO CLI."
    exit 1
fi

timestamp=$(date +%Y-%m-%d-%H-%M)
log_file="./logs/rawdata-${timestamp}.log"

echo "Logging serial output to $log_file"
echo "Press Ctrl+C to stop monitoring"
mkdir -p ./logs
$PLATFORMIO_BIN device monitor --environment $1 --quiet --no-reconnect > "$log_file"