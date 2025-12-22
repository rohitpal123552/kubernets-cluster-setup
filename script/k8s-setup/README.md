
---

```markdown
## Kubernetes Cluster Setup (Single-node & Multi-node)

This repository provides an **automated Bash-based setup** for installing a
**Kubernetes v1.32.x cluster** on **Ubuntu** using **kubeadm** and
**containerd v1.7.25**.

The setup supports:
- ✅ Single-node Kubernetes cluster
- ✅ Multi-node Kubernetes cluster (1 master + N workers)
- ✅ Passwordless sudo
- ✅ Pre-flight checks
- ✅ SSH-based worker bootstrap (run once from master)
```
---

## Directory Structure

```
k8s-setup/
├── common.sh           # Common setup for all nodes
├── control-plane.sh    # Control-plane (master) setup
├── worker.sh           # Worker node join logic
├── k8s-setup.sh        # Main entry-point script
└── README.md

````

---

## Prerequisites

### 1. Ubuntu OS
- Ubuntu **20.04 / 22.04**
- Same OS on all nodes

### 2. Passwordless sudo (REQUIRED)
Run this on **all nodes**:

```bash
echo "ubuntu ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/ubuntu >/dev/null
````

Verify:

```bash
sudo -n true && echo "Passwordless sudo enabled"
```

---

### 3. SSH Key-based Access (REQUIRED for multi-node)

From the **master node**:

```bash
ssh-copy-id ubuntu@<worker-ip>
```

Ensure:

```bash
ssh ubuntu@<worker-ip> hostname
```

works **without password**.

---

## Supported Versions

| Component  | Version |
| ---------- | ------- |
| Kubernetes | 1.32.x  |
| containerd | 1.7.25  |
| CNI        | Calico  |

---

## Pre-flight Checks

The script automatically validates:

* Ubuntu OS
* Passwordless sudo
* Minimum CPU & RAM
* Required ports
* Swap status

If any check fails, the script **stops immediately**.

---

## Usage

### Single-node Cluster

Run on **one machine only**:

```bash
./k8s-setup.sh singlenode --master-ip 192.168.1.10
```

This will:

* Install containerd
* Install Kubernetes
* Initialize control plane
* Install Calico
* Schedule workloads on master

---

### Multi-node Cluster

Run **only on the master node**:

```bash
./k8s-setup.sh multinode \
  --master-ip 192.168.1.10 \
  --workers 192.168.1.11,192.168.1.12
```

This will:

* Configure master
* Generate `kubeadm join` command
* SSH into workers
* Install dependencies on workers
* Join workers to the cluster automatically

 You **do not need** to manually log into worker nodes.

---

## Verify Cluster

```bash
kubectl get nodes -o wide
kubectl get pods -A
```

Expected:

* Master node in `Ready`
* All worker nodes in `Ready`
* Calico pods running

---

Happy Kubernetes learning 🚀

