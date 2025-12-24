#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/common.sh"
source "$SCRIPT_DIR/control-plane.sh"
source "$SCRIPT_DIR/worker.sh"
source "$SCRIPT_DIR/ssh-utils.sh"
source "$SCRIPT_DIR/cleanup-k8s-setup.sh"

# Helper function
usage() {
    cat <<EOF

Usage:
  ./k8s-setup.sh mode <singlenode|multinode|worker> [options]

------------------------------------------------------------
Modes:

  singlenode     Setup a single-node Kubernetes cluster
  multinode     Setup a multi-node Kubernetes cluster
  worker        Internal use only (worker join)
  reset         FULL cleanup / destroy Kubernetes cluster

------------------------------------------------------------
Single-node cluster setup:

  ./k8s-setup.sh mode singlenode \\
    --master-ip <MASTER_IP>

Example:
  ./k8s-setup.sh mode singlenode --master-ip 192.168.1.10

------------------------------------------------------------
Multi-node cluster setup:

  ./k8s-setup.sh mode multinode \\
    --master-ip <MASTER_IP> \\
    --workers <IP1,IP2> \\
    --ssh-user <USER> \\
    --ssh-password <PASSWORD>

Example:
  ./k8s-setup.sh mode multinode \\
    --master-ip 192.168.1.10 \\
    --workers 192.168.1.11,192.168.1.12 \\
    --ssh-user ubuntu \\
    --ssh-password MyPassword

------------------------------------------------------------
Worker node (auto-invoked by master):

  ./k8s-setup.sh mode worker \\
    --join-cmd "<kubeadm join command>"

------------------------------------------------------------
FULL RESET / DESTROY (IRREVERSIBLE):

  ./k8s-setup.sh mode singlenode \\
    --master-ip <MASTER_IP> \\
    --reset

Example:
  ./k8s-setup.sh mode singlenode --master-ip 192.168.1.10 --reset

  ./k8s-setup.sh mode multinode \\
    --reset \\
    --master-ip <MASTER_IP> \\
    --workers <IP1,IP2> \\
    --ssh-user <USER> \\
    --ssh-password <PASSWORD>

Example:
  ./k8s-setup.sh mode multinode \\
    --reset \\
    --master-ip 192.168.1.10 \\
    --workers 192.168.1.11,192.168.1.12 \\
    --ssh-user ubuntu \\
    --ssh-password MyPassword

------------------------------------------------------------
Common Options:

  --master-ip     Kubernetes control-plane IP
  --workers       Comma-separated worker node IPs
  --ssh-user      SSH username (non-root, e.g. ubuntu)
  --ssh-password  SSH password (used once to copy SSH key)
  --reset         REQUIRED flag for reset mode
  --join-cmd      kubeadm join command (internal use)

------------------------------------------------------------
Notes:

- Run the script as a NON-ROOT user (e.g. ubuntu)
- User must have passwordless sudo
- SSH key-based access is required for multi-node setup
- --reset is mandatory for reset mode (safety)

------------------------------------------------------------
EOF
    exit 1
}


bootstrap_workers_ssh() {
    ssh_preflight_master

    IFS=',' read -ra WORKER_IPS <<< "$WORKERS"

    for ip in "${WORKER_IPS[@]}"; do
        copy_ssh_key_to_worker "$ip"
        validate_ssh_access "$ip"
    done
}

# MODE="$2"
# shift 2 || true
DESTROY_ALL="false"
MODE="${2:-}"
shift 2 || true

case "$MODE" in
    singlenode|multinode|worker)
        ;;
    *)
        echo "Invalid mode: $MODE"
        usage
        ;;
esac

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
        --ssh-user)
            SSH_USER="$2"
            shift 2
            ;;
        --ssh-password)
            SSH_PASSWORD="$2"
            shift 2
            ;;
        --join-cmd)
            JOIN_CMD="$2"
            shift 2
            ;;
        --reset)
            DESTROY_ALL="true"
            shift
            ;;
        *)
            usage
            ;;
    esac
done

# cleanup setup 
if [[ "${DESTROY_ALL:-}" == "true" ]]; then

    if [[ "${MODE_TYPE:-}" == "multinode" ]]; then
        echo "[RESET] Multi-node detected"

        drain_all_workers || true

        echo "[RESET] Cleaning master node"
        full_cleanup_node

        if [[ -n "${WORKERS:-}" ]]; then
            ssh_preflight_master

            IFS=',' read -ra WORKER_IPS <<< "$WORKERS"
            for ip in "${WORKER_IPS[@]}"; do
                echo "[RESET] Cleaning worker $ip"

                ssh_exec "$ip" "
                    $(declare -f full_cleanup_node)
                    full_cleanup_node
                "
            done
        fi
        exit 1
    else
        echo "[RESET] Single-node detected"
        echo "[RESET] Cleaning master node"
        full_cleanup_node
        exit 1
    fi
fi

case "$MODE" in
    singlenode)
        [[ -z "${MASTER_IP:-}" ]] && usage
        common_setup
        init_control_plane
        ;;
    multinode)
        [[ -z "${MASTER_IP:-}" || -z "${WORKERS:-}" || -z "${SSH_USER:-}" || -z "${SSH_PASSWORD:-}" ]] && usage

        common_setup
        init_control_plane

        # bootstrap worker ssh
        bootstrap_workers_ssh

        JOIN_CMD=$(kubeadm token create --print-join-command)

        IFS=',' read -ra WORKER_IPS <<< "$WORKERS"
        for ip in "${WORKER_IPS[@]}"; do
            echo "Configuring worker $ip"

            scp_dir "$ip"

            ssh_exec "$ip" "
                cd /tmp/k8s-setup &&
                chmod +x *.sh &&
                sudo ./k8s-setup.sh mode worker --join-cmd '$JOIN_CMD'
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
