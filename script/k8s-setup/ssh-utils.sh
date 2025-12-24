#!/usr/bin/env bash
set -Eeuo pipefail

log() {
    echo "[SSH] $(date '+%F %T') - $1"
}

#####################################
# SSH KEY MANAGEMENT
#####################################
generate_ssh_key() {
    log "Checking SSH key"

    if [[ ! -f "$HOME/.ssh/id_rsa" ]]; then
        log "SSH key not found, generating"
        ssh-keygen -t rsa -b 4096 -N "" -f "$HOME/.ssh/id_rsa"
    else
        log "SSH key already exists"
    fi
}

verify_and_install_sshpass() {
    if ! command -v sshpass &>/dev/null; then
        log "Installing sshpass"
        sudo apt-get update
        sudo apt-get install -y sshpass
    fi
}

#####################################
# SSH OPERATIONS
#####################################
ssh_exec() {
    local ip="$1"
    shift
    ssh -o StrictHostKeyChecking=no \
        "${SSH_USER}@${ip}" "$@"
}

scp_dir() {
    local ip="$1"
    scp -r -o StrictHostKeyChecking=no \
        "$SCRIPT_DIR" "${SSH_USER}@${ip}:/tmp/k8s-setup"
}

ssh_preflight_master() {
    log "Running SSH pre-flight on MASTER"

    # Ensure openssh client
    if ! command -v ssh &>/dev/null; then
        log "Installing openssh-client"
        sudo apt-get update
        sudo apt-get install -y openssh-client
    fi

    # Ensure ~/.ssh exists
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"

    # Ensure SSH key
    generate_ssh_key

    # Validate local SSH
    log "Validating local SSH"
    ssh -o BatchMode=yes localhost hostname >/dev/null 2>&1 || {
        echo "SSH not working locally on master"
        echo "Run: sudo systemctl enable --now ssh"
        exit 1
    }

    log "Master SSH pre-flight OK"
}

copy_ssh_key_to_worker() {
    local ip="$1"

    [[ -z "${SSH_PASSWORD:-}" ]] && {
        echo "--ssh-password required for SSH bootstrap"
        exit 1
    }

    verify_and_install_sshpass

    log "Copying SSH key to ${SSH_USER}@${ip}"
    sshpass -p "$SSH_PASSWORD" ssh-copy-id \
        -o StrictHostKeyChecking=no \
        "${SSH_USER}@${ip}"
}

validate_ssh_access() {
    local ip="$1"

    log "Validating SSH access to $ip"
    ssh -o BatchMode=yes \
        -o ConnectTimeout=5 \
        -o StrictHostKeyChecking=no \
        "${SSH_USER}@${ip}" hostname >/dev/null 2>&1 || {
            echo "SSH validation failed for $ip"
            exit 1
        }

    log "SSH validated for $ip"
}
