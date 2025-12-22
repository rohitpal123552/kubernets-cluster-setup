#!/usr/bin/env bash
set -Eeuo pipefail

POD_CIDR="192.168.0.0/16"

log() {
    echo "[MASTER] $(date '+%F %T') - $1"
}

init_control_plane() {
    log "Initializing control plane"

    sudo kubeadm init \
        --apiserver-advertise-address="$MASTER_IP" \
        --pod-network-cidr="$POD_CIDR"

    # kubeadm init --kubernetes-version=${K8S_VERSION} --pod-network-cidr=${POD_CIDR} --ignore-preflight-errors=NumCPU
    mkdir -p $HOME/.kube
    sudo cp /etc/kubernetes/admin.conf $HOME/.kube/config
    sudo chown $(id -u):$(id -g) $HOME/.kube/config

    log "Installing Calico CNI"
    kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.28.0/manifests/calico.yaml

    log "Join command:"
    kubeadm token create --print-join-command
}
