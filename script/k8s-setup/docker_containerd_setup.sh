
#!/usr/bin/env bash

# Installs containerd and Docker
# update DOCKER_VERSION and CONTAINERD_VERSION accordingly.

set -euo pipefail
set -o errtrace

trap 'echo "Error on line $LINENO: $BASH_COMMAND"; exit 1' ERR

# -----------------------------
# Version pins
# -----------------------------
DOCKER_VERSION="5:28.1.1-1~ubuntu.22.04~jammy"
CONTAINERD_VERSION="1.7.25-1"

# -----------------------------
# Config
# -----------------------------
HOLD_PACKAGES=true   # Set to false if you do not want apt-mark hold
SUDO=""              # Auto-detect sudo usage
# UBUNTU_CODENAME=""

log()   { echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] $*"; }
warn()  { echo -e "⚠️  $*"; }
ok()    { echo -e "✅ $*"; }

detect_env() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    SUDO="sudo"
  fi

  # # Try lsb_release, fallback to /etc/os-release
  # if UBUNTU_CODENAME=$(lsb_release -cs 2>/dev/null); then
  #   : # OK
  # else
  #   # shellcheck disable=SC1091
  #   source /etc/os-release || true
  #   UBUNTU_CODENAME="${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}"
  # fi

  # if [[ -z "${UBUNTU_CODENAME}" ]]; then
  #   warn "Could not determine Ubuntu codename. Proceeding, but repository setup may fail."
  # else
  #   log "Detected Ubuntu codename: ${UBUNTU_CODENAME}"
  # fi

  # if [[ "${UBUNTU_CODENAME}" != "jammy" ]]; then
  #   warn "You are on '${UBUNTU_CODENAME}'. The Docker version pin '${DOCKER_VERSION}' is for 'jammy'."
  #   warn "If installation fails, update DOCKER_VERSION to match your codename."
  # fi
}


# -----------------------------------------
# Deep clean of old Docker and containerd
# -----------------------------------------
remove_old_docker() {
  log "Cleaning any existing Docker and containerd installations..."

  log "Unhold Containerd and Docker packages"
  sudo apt-mark unhold containerd.io docker-ce docker-ce-cli docker-buildx-plugin docker-compose-plugin

  # Stop services if present
  ${SUDO} systemctl stop docker 2>/dev/null || true
  ${SUDO} systemctl stop containerd 2>/dev/null || true

  # Disable services
  ${SUDO} systemctl disable docker 2>/dev/null || true
  ${SUDO} systemctl disable containerd 2>/dev/null || true

  log "Removing any old Docker and Containerd versions..."
  ${SUDO} apt-get remove -y docker-ce docker-ce-cli docker-ce-rootless-extras \
      docker-buildx-plugin docker-compose-plugin docker.io docker-engine \
      containerd containerd.io runc 2>/dev/null || true

  # Purge packages
  log "Purging Docker and containerd packages..."
  ${SUDO} apt-get purge -y docker-ce docker-ce-cli docker-ce-rootless-extras \
      docker-buildx-plugin docker-compose-plugin docker.io docker-engine \
      containerd containerd.io runc 2>/dev/null || true

  # Autoremove residuals
  ${SUDO} apt-get autoremove -y 2>/dev/null || true

  # # Remove systemd unit overrides/sockets if present
  # log "Removing systemd units and sockets..."
  # ${SUDO} rm -f /etc/systemd/system/docker.service.d/* 2>/dev/null || true
  # ${SUDO} rm -rf /etc/systemd/system/docker.service.d 2>/dev/null || true
  # ${SUDO} rm -f /etc/systemd/system/containerd.service.d/* 2>/dev/null || true
  # ${SUDO} rm -rf /etc/systemd/system/containerd.service.d 2>/dev/null || true
  # ${SUDO} rm -f /etc/systemd/system/docker.service 2>/dev/null || true
  # ${SUDO} rm -f /etc/systemd/system/docker.socket 2>/dev/null || true
  # ${SUDO} rm -f /lib/systemd/system/docker.service 2>/dev/null || true
  # ${SUDO} rm -f /lib/systemd/system/docker.socket 2>/dev/null || true
  # ${SUDO} rm -f /lib/systemd/system/containerd.service 2>/dev/null || true
  # ${SUDO} systemctl daemon-reload || true

  # # Remove runtime sockets and pid files
  # ${SUDO} rm -f /var/run/docker.pid /var/run/docker.sock 2>/dev/null || true
  # ${SUDO} rm -f /run/containerd/containerd.sock /run/containerd.pid 2>/dev/null || true

  # Remove configuration directories
  log "Removing config & data directories..."
  ${SUDO} rm -rf /etc/docker 2>/dev/null || true
  ${SUDO} rm -rf /etc/containerd 2>/dev/null || true

  # Remove data directories (this nukes images/containers)
  ${SUDO} rm -rf /var/lib/docker 2>/dev/null || true
  ${SUDO} rm -rf /var/lib/containerd 2>/dev/null || true

  # Remove run directories
  ${SUDO} rm -rf /run/docker 2>/dev/null || true
  ${SUDO} rm -rf /run/containerd 2>/dev/null || true
  ${SUDO} rm -rf /var/run/docker 2>/dev/null || true
  ${SUDO} rm -rf /var/run/containerd 2>/dev/null || true

  # Clean cache and APT residual config files
  ${SUDO} rm -rf /var/cache/docker 2>/dev/null || true
  ${SUDO} rm -rf /var/log/docker* 2>/dev/null || true
  ${SUDO} rm -rf /var/log/containerd* 2>/dev/null || true

  # Optional: remove old repo list to avoid conflicts (we add it cleanly later)
  ${SUDO} rm -f /etc/apt/sources.list.d/docker.list 2>/dev/null || true
  ${SUDO} rm -f /etc/apt/keyrings/docker.gpg 2>/dev/null || true

  # Update package lists after purge
  ${SUDO} apt-get update -y || true

  ok "Old Docker and containerd cleaned up thoroughly."
}

install_prereqs() {
  log "Installing required packages..."
  ${SUDO} apt-get update -y
  ${SUDO} apt-get install -y ca-certificates curl gnupg lsb-release
}

setup_docker_repo() {
  log "Adding Docker's official GPG key (idempotent)..."
  ${SUDO} install -m 0755 -d /etc/apt/keyrings
  # Write to a temp file then move to avoid partial writes
  TMP_KEY="$(mktemp)"
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o "${TMP_KEY}"
  ${SUDO} gpg --dearmor < "${TMP_KEY}" | ${SUDO} tee /etc/apt/keyrings/docker.gpg >/dev/null
  rm -f "${TMP_KEY}"
  ${SUDO} chmod a+r /etc/apt/keyrings/docker.gpg

  # log "Setting up Docker APT repository for '${UBUNTU_CODENAME:-unknown}'..."
  log "Setting up Docker APT repository..."
  REPO_LINE="deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
  REPO_FILE="/etc/apt/sources.list.d/docker.list"

  # Add repo only if absent
  if [[ -f "${REPO_FILE}" ]] && grep -q "download.docker.com/linux/ubuntu" "${REPO_FILE}"; then
    log "Docker repo already configured."
  else
    echo "${REPO_LINE}" | ${SUDO} tee "${REPO_FILE}" >/dev/null
    log "Updating APT with Docker repo..."
  fi

  ${SUDO} apt-get update -y
}

install_containerd() {
  log "Installing containerd.io=${CONTAINERD_VERSION} ..."
  # Allow downgrades in case a newer version is present
  ${SUDO} apt-get install -y --allow-downgrades containerd.io="${CONTAINERD_VERSION}"

  log "Enabling & starting containerd service..."
  ${SUDO} systemctl enable containerd
  ${SUDO} systemctl start containerd

  log "Verifying containerd..."
  sleep 10s
  containerd --version || { warn "containerd --version failed"; true; }
  ${SUDO} systemctl --no-pager --full status containerd | sed -n '1,10p' || true

  if [[ "${HOLD_PACKAGES}" == "true" ]]; then
    ${SUDO} apt-mark hold containerd.io
    log "Held containerd.io at ${CONTAINERD_VERSION}"
  fi

  ok "containerd.io ${CONTAINERD_VERSION} installed and running."
}

install_docker() {
  log "Installing Docker (CE/CLI/Buildx/Compose) pinned to ${DOCKER_VERSION} ..."
  ${SUDO} apt-get install -y --allow-downgrades \
    docker-ce="${DOCKER_VERSION}" \
    docker-ce-cli="${DOCKER_VERSION}" \
    docker-buildx-plugin \
    docker-compose-plugin

  log "Enabling & starting docker service..."
  ${SUDO} systemctl enable docker
  ${SUDO} systemctl start docker

  log "Testing Docker installation..."
  sleep 30s
  ${SUDO} docker version || { warn "docker version failed"; true; }
  log "Helpers:"
  which docker-proxy || true
  which docker-init || true

  # Run hello-world to validate runtime & pull
  ${SUDO} docker run --rm hello-world

  if [[ "${HOLD_PACKAGES}" == "true" ]]; then
    ${SUDO} apt-mark hold docker-ce docker-ce-cli docker-buildx-plugin docker-compose-plugin
    log "Held Docker packages at specified versions"
  fi

  ok "Docker ${DOCKER_VERSION} installed and verified."
}

main() {
  detect_env
  remove_old_docker
  install_prereqs
  setup_docker_repo

  # Separate steps
  install_containerd
  install_docker

  ok "Docker v28.1.1 and containerd v${CONTAINERD_VERSION} installed successfully!"
}

main "$@"
