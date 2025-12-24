# Kubernetes Cluster Setup (Single-node & Multi-node)

This repository provides a **Bash-based automation** to set up and manage a **Kubernetes v1.32.x cluster** on **Ubuntu** using **kubeadm** and **containerd v1.7.25**.

The solution is designed for **fresh VMs**, supports **non-root users**, and enables **fully automated multi-node provisioning via SSH**.

---

##  Features

* ✅ Single-node Kubernetes cluster
* ✅ Multi-node Kubernetes cluster (1 control-plane + N workers)
* ✅ Explicit **mode-based CLI** (`mode singlenode | multinode | worker`)
* ✅ SSH key generation & distribution (automatic)
* ✅ Passwordless sudo validation
* ✅ Pre-flight checks (OS, CPU, RAM, swap, ports)
* ✅ Full **cluster destroy / cleanup** mode (safe & irreversible)
* ✅ Kubernetes **v1.32.x**
* ✅ containerd **v1.7.25**
* ✅ Calico CNI
* ✅ Run once from master — workers are auto-configured

---

##  Directory Structure

```
k8s-setup/
├── common.sh               # Shared logic (pre-flight, install, cleanup)
├── control-plane.sh        # Control-plane (master) setup & drain logic
├── worker.sh               # Worker node join logic
├── ssh-utils.sh            # SSH key generation, copy & validation
├── k8s-setup.sh            # Main entry-point (mode-based CLI)
├── cleanup-k8s-setup.sh.   # Tear down k8s completely
└── README.md
```

---

##  Prerequisites

### 1. Supported OS

* Ubuntu **20.04 / 22.04**
* Same OS version on all nodes
* Fresh VM recommended

---

### 2. Non-root User with Passwordless sudo (REQUIRED)

Run on **ALL nodes**:

```bash
echo "ubuntu ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/ubuntu >/dev/null
```

Verify:

```bash
sudo -n true && echo "Passwordless sudo enabled"
```

> ⚠️ The script must be run as a **non-root user** (e.g., `ubuntu`).

---

### 3. SSH Access (Multi-node Only)

For **multi-node setups**, the script will:

* Generate SSH keys on the master (if missing)
* Copy keys to workers using password (one time)
* Validate passwordless SSH

You **do not need to manually run `ssh-copy-id`**.

---

##  Supported Versions

| Component  | Version |
| ---------- | ------- |
| Kubernetes | 1.32.x  |
| containerd | 1.7.25  |
| CNI        | Calico  |

---

##  Pre-flight Checks

The script automatically validates:

* Ubuntu OS compatibility
* Passwordless sudo
* CPU & RAM requirements
* Swap disabled
* Required ports availability
* Local SSH readiness (master)

If **any check fails**, execution **stops immediately**.

---

##  Usage

All commands follow this pattern:

```
./k8s-setup.sh mode <MODE> [OPTIONS]
```

---

###  Single-node Cluster

Run on **one machine only**:

```bash
./k8s-setup.sh mode singlenode \
  --master-ip 192.168.1.10
```

This will:

* Install containerd
* Install kubeadm, kubelet, kubectl
* Initialize control-plane
* Install Calico CNI
* Enable scheduling on control-plane

---

### 🔹 Multi-node Cluster

Run **ONLY on the master node**:

```bash
./k8s-setup.sh mode multinode \
  --master-ip 192.168.1.10 \
  --workers 192.168.1.11,192.168.1.12 \
  --ssh-user ubuntu \
  --ssh-password MyPassword
```

This will:

* Perform master pre-flight checks
* Generate SSH keys (if missing)
* Copy SSH keys to workers
* Validate passwordless SSH
* Configure master node
* Generate `kubeadm join` command
* SSH into worker nodes
* Install dependencies on workers
* Join workers to the cluster automatically

👉 **You do NOT need to manually log into worker nodes.**

---

###  Worker Mode (Internal)

Automatically executed on worker nodes by the master:

```bash
./k8s-setup.sh mode worker \
  --join-cmd "<kubeadm join command>"
```

>  Do NOT run this manually.

---

##  FULL RESET / DESTROY (IRREVERSIBLE)

This mode **completely removes Kubernetes from all nodes**.

It will:

* Drain worker nodes (multi-node only)
* Reset kubeadm
* Remove kubeadm / kubelet / kubectl packages
* Remove containerd state
* Remove CNI & iptables rules
* Remove all Kubernetes data & configs

###  Safety Flag Required

You **MUST** pass `--reset` to proceed.

---

###  Reset Single-node Cluster

```bash
./k8s-setup.sh mode singlenode \
  --reset \
  --master-ip 192.168.1.10
```

---

###  Reset Multi-node Cluster

```bash
./k8s-setup.sh mode multinode \
  --reset \
  --master-ip 192.168.1.10 \
  --workers 192.168.1.11,192.168.1.12 \
  --ssh-user ubuntu \
  --ssh-password MyPassword
```

---

##  Verify Cluster

After setup:

```bash
kubectl get nodes -o wide
kubectl get pods -A
```

Expected:

* All nodes in `Ready` state
* Calico pods running
* Control-plane & workers healthy

---

##  Important Notes

* Run scripts as **non-root user only**
* Passwordless sudo is mandatory
* SSH password is used **once only** (key bootstrap)
* Reset mode is **destructive and irreversible**
* Safe to re-run setup after reset

---

##  Summary

This repository provides a **clean, repeatable, and safe** way to:

* Build Kubernetes clusters
* Tear down completely
* Rebuild from scratch

