#!/usr/bin/env bash
set -Eeuo pipefail

CRI_VERSION="1.32"
K8S_VERSION="1.32.1"
CONTAINERD_VERSION="1.7.25"

log() {
    echo "[COMMON] $(date '+%F %T') - $1"
}

preflight_checks() {
    log "Running pre-flight checks"

    # Root / sudo
    if ! sudo -n true 2>/dev/null; then
        echo "Passwordless sudo required"
        exit 1
    fi

    # OS check
    source /etc/os-release
    if [[ "$ID" != "ubuntu" ]]; then
        echo "Only Ubuntu is supported"
        exit 1
    fi

    # # CPU / RAM
    # CPU=$(nproc)
    # RAM=$(free -m | awk '/Mem:/ {print $2}')
    # if (( CPU < 2 || RAM < 1700 )); then
    #     echo "Minimum 2 CPU and 2GB RAM required"
    #     exit 1
    # fi

    # Ports
    for port in 6443 10250; do
        if ss -lnt | grep -q ":$port "; then
            echo "Port $port already in use"
            exit 1
        fi
    done

    # Swap
    if swapon --summary | grep -q .; then
        echo "Swap is enabled (will be disabled)"
    fi

    log "Pre-flight checks passed"
}

disable_swap() {
    log "Disabling swap"
    sudo swapoff -a
    sudo sed -i '/ swap / s/^/#/' /etc/fstab
}

load_kernel_modules() {
    log "Loading kernel modules..."
    cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

    sudo modprobe overlay
    sudo modprobe br_netfilter
}

set_sysctl_params() {
    log "Setting sysctl params..."
    cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

    sudo sysctl --system
}

install_containerd() {
    log "Installing containerd ${CONTAINERD_VERSION}"
    sudo apt update
    sudo apt install -y curl tar

    curl -LO https://github.com/containerd/containerd/releases/download/v${CONTAINERD_VERSION}/containerd-${CONTAINERD_VERSION}-linux-amd64.tar.gz
    sudo tar Cxzvf /usr/local containerd-${CONTAINERD_VERSION}-linux-amd64.tar.gz

    sudo mkdir -p /etc/containerd
    containerd config default | sudo tee /etc/containerd/config.toml
    sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

    sudo curl -Lo /etc/systemd/system/containerd.service \
      https://raw.githubusercontent.com/containerd/containerd/main/containerd.service

    sudo systemctl daemon-reexec
    sudo systemctl daemon-reload
    sudo systemctl enable --now containerd
}

install_kubernetes() {
    log "Installing Kubernetes ${CRI_VERSION}.x"

    sudo apt update
    sudo apt install -y apt-transport-https ca-certificates curl gpg

    curl -fsSL https://pkgs.k8s.io/core:/stable:/v${CRI_VERSION}/deb/Release.key |
      sudo gpg --dearmor -o /etc/apt/keyrings/k8s.gpg

    echo "deb [signed-by=/etc/apt/keyrings/k8s.gpg] \
https://pkgs.k8s.io/core:/stable:/v${CRI_VERSION}/deb/ /" |
      sudo tee /etc/apt/sources.list.d/kubernetes.list

    sudo apt update
    apt-get install -y kubelet=${K8S_VERSION}-1.1 kubeadm=${K8S_VERSION}-1.1 kubectl=${K8S_VERSION}-1.1

    sudo apt-mark hold kubelet kubeadm kubectl
}

common_setup() {
    preflight_checks
    disable_swap
    load_kernel_modules
    set_sysctl_params
    # install_containerd
    install_kubernetes
}
