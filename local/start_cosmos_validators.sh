#!/usr/bin/env bash
# Start (or restart) the 4 Gaia validators that run_cosmos_node.sh already
# initialized. Does NOT touch genesis, keys or relayer/.env.
#
#   ./scripts/local/start_cosmos_validators.sh          # start all
#   ./scripts/local/start_cosmos_validators.sh stop     # stop all
#   ./scripts/local/start_cosmos_validators.sh status   # show what's up

set -euo pipefail

cd "$(dirname "$0")/../.."

. ./scripts/local/gaiad_binary.sh

HOMES=(
    "$HOME/.gaia"
    "$HOME/.gaia-val2"
    "$HOME/.gaia-val3"
    "$HOME/.gaia-val4"
)
VAL_KEYS=(val1 val2 val3 val4)
RPC_PORTS=(26657 26757 26857 26957)

PID_DIR="${PID_DIR:-$HOME/.gaia-pids}"
mkdir -p "$PID_DIR"

pid_file_for() { echo "$PID_DIR/${VAL_KEYS[$1]}.pid"; }

running_pid() {
    local f
    f="$(pid_file_for "$1")"
    [ -f "$f" ] || return 1
    local pid
    pid="$(cat "$f")"
    kill -0 "$pid" 2>/dev/null || return 1
    echo "$pid"
}

start_all() {
    for i in "${!HOMES[@]}"; do
        local home="${HOMES[$i]}"

        if [ ! -f "$home/config/genesis.json" ]; then
            echo "No genesis in $home — run scripts/local/run_cosmos_node.sh first." >&2
            exit 1
        fi

        if pid="$(running_pid "$i")"; then
            echo "  ${VAL_KEYS[$i]} already running (pid $pid)"
            continue
        fi

        nohup "$GAIAD" start --home "$home" >> "$home/gaiad.log" 2>&1 &
        echo "$!" > "$(pid_file_for "$i")"
        echo "  ${VAL_KEYS[$i]} pid=$! rpc=tcp://127.0.0.1:${RPC_PORTS[$i]} log=$home/gaiad.log"
    done
    echo "Detached — closing this shell will not stop them."
}

stop_all() {
    for i in "${!HOMES[@]}"; do
        if pid="$(running_pid "$i")"; then
            kill "$pid" 2>/dev/null || true
            echo "  stopped ${VAL_KEYS[$i]} (pid $pid)"
        fi
        rm -f "$(pid_file_for "$i")"
    done
}

status_all() {
    for i in "${!HOMES[@]}"; do
        if pid="$(running_pid "$i")"; then
            echo "  ${VAL_KEYS[$i]} up   pid=$pid rpc=tcp://127.0.0.1:${RPC_PORTS[$i]}"
        else
            echo "  ${VAL_KEYS[$i]} down"
        fi
    done
}

case "${1:-start}" in
    start)  start_all ;;
    stop)   stop_all ;;
    status) status_all ;;
    *) echo "usage: $0 [start|stop|status]" >&2; exit 1 ;;
esac
