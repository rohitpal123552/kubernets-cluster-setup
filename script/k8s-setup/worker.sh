#!/usr/bin/env bash
set -Eeuo pipefail

log() {
    echo "[WORKER] $(date '+%F %T') - $1"
}

join_worker() {
    if [[ -z "${JOIN_CMD:-}" ]]; then
        echo "JOIN_CMD not provided"
        exit 1
    fi

    log "Joining worker node"
    sudo $JOIN_CMD
}
