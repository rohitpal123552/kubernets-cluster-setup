#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/common.sh"
source "$SCRIPT_DIR/control-plane.sh"
source "$SCRIPT_DIR/worker.sh"

ssh_exec() {
    local ip="$1"
    shift
    ssh -o StrictHostKeyChecking=no ubuntu@"$ip" "$@"
}

scp_dir() {
    local ip="$1"
    scp -r -o StrictHostKeyChecking=no "$SCRIPT_DIR" ubuntu@"$ip:/tmp/k8s-setup"
}

usage() {
    echo "Usage:"
    echo
    echo "Single-node cluster:"
    echo "  ./k8s-setup.sh singlenode --master-ip <MASTER_IP>"
    echo
    echo "  Example:"
    echo "  ./k8s-setup.sh singlenode --master-ip 192.168.1.10"
    echo
    echo "Multi-node cluster:"
    echo "  ./k8s-setup.sh multinode --master-ip <MASTER_IP> --workers <IP1,IP2>"
    echo
    echo "  Example:"
    echo "  ./k8s-setup.sh multinode --master-ip 192.168.1.10 --workers 192.168.1.11,192.168.1.12"
    echo
    exit 1
}

MODE="$1"
shift || true

#Argument parsing
while [[ $# -gt 0 ]]; do
    case "$1" in
        --master-ip)
            MASTER_IP="$2"
            shift 2
            ;;
        --workers)
            WORKERS="$2"
            shift 2
            ;;
        --join-cmd)
            JOIN_CMD="$2"
            shift 2
            ;;
        *)
            usage
            ;;
    esac
done


case "$MODE" in
    singlenode)
        [[ -z "${MASTER_IP:-}" ]] && usage
        common_setup
        init_control_plane
        ;;
    multinode)
        [[ -z "${MASTER_IP:-}" || -z "${WORKERS:-}" ]] && usage

        # Setup master
        common_setup
        init_control_plane

        JOIN_CMD=$(kubeadm token create --print-join-command)

        # Setup workers
        IFS=',' read -ra WORKER_IPS <<< "$WORKERS"
        for ip in "${WORKER_IPS[@]}"; do
            echo " Configuring worker $ip"

            scp_dir "$ip"

            ssh_exec "$ip" "
                chmod +x /tmp/k8s-setup/*.sh &&
                cd /tmp/k8s-setup &&
                sudo ./k8s-setup.sh worker --join-cmd '$JOIN_CMD'
            "
        done
        ;;
    worker)
        [[ -z "${JOIN_CMD:-}" ]] && usage
        common_setup
        join_worker
        ;;
    *)
        usage
        ;;
esac

