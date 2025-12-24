#!/usr/bin/env bash

drain_all_workers() {
    echo "[DRAIN] Draining worker nodes"

    kubectl get nodes --no-headers | awk '{print $1}' | grep -v "$(hostname)" | while read -r node; do
        kubectl drain "$node" \
            --ignore-daemonsets \
            --delete-emptydir-data \
            --force || true
    done

    echo "[DRAIN] Workers drained"
}


full_cleanup_node() {
    echo "[DESTROY] Full cleanup on $(hostname)"

    # Stop services
    sudo systemctl stop kubelet || true
    # sudo systemctl stop containerd || true

    # Reset kubeadm if exists
    sudo kubeadm reset -f || true

    # Remove Kubernetes packages
    sudo apt-get purge -y kubeadm kubelet kubectl kubernetes-cni cri-tools || true
    sudo apt-get autoremove -y || true
    sudo apt-get autoclean || true

    # Remove Kubernetes dirs
    sudo rm -rf \
        /etc/kubernetes \
        /var/lib/kubelet \
        /var/lib/etcd \
        /etc/cni \
        /opt/cni \
        /var/run/kubernetes \
        /var/lib/cni \
        ~/.kube

    # Flush iptables
    sudo iptables -F || true
    sudo iptables -t nat -F || true
    sudo iptables -t mangle -F || true
    sudo iptables -X || true

    # Flush IPVS
    sudo ipvsadm --clear || true

    # # Remove containerd data
    # sudo rm -rf /var/lib/containerd
    # sudo rm -rf /etc/containerd

    # Remove binaries if still exist
    sudo rm -f /usr/bin/kubeadm /usr/bin/kubelet /usr/bin/kubectl
    sudo rm -f /usr/local/bin/kubeadm /usr/local/bin/kubelet /usr/local/bin/kubectl
    sudo rm -f /etc/systemd/system/kubelet.service.d/10-kubeadm.conf

    # Reload systemd
    sudo systemctl daemon-reexec
    sudo systemctl daemon-reload

    echo "[DESTROY] Node cleaned completely"
}
