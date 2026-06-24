#!/bin/bash
#
# Installs rootless Docker for a specified user, run as root.
#
# Usage: bash install_docker_rootless_from_root.sh <username>
#
# Intended for automated provisioning (eg. cloud-init) where the script runs
# as root but Docker should be installed rootless for a non-root user.

set -euo pipefail

TARGET_USER="${1:?Usage: $0 <username>}"
TARGET_UID=$(id -u "$TARGET_USER")


# -- Docker

# -- Docker -- Add Docker's official GPG key and Ubuntu repository
apt-get update
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" > /etc/apt/sources.list.d/docker.list
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# -- Docker -- Install rootless prerequisites
apt-get install -y uidmap

# -- Docker -- Stop system Docker daemon — rootless Docker replaces it
systemctl disable --now docker.service docker.socket


# -- Rootless Docker

# -- Rootless Docker -- Enable linger so daemon starts at boot without the user being logged in
loginctl enable-linger "$TARGET_USER"

# -- Rootless Docker -- Ensure the user runtime directory exists
#
# Normally created by systemd-logind on login, but in cloud-init there is no
# login session for the user yet.
mkdir -p "/run/user/${TARGET_UID}"
chown "$TARGET_USER:$TARGET_USER" "/run/user/${TARGET_UID}"
chmod 700 "/run/user/${TARGET_UID}"

# -- Rootless Docker -- Install rootless Docker as the target user
#
# XDG_RUNTIME_DIR must be set explicitly — when running via su in a non-login
# context (eg. cloud-init), the systemd user session is not active so the
# variable is not set automatically.
su - "$TARGET_USER" -c "XDG_RUNTIME_DIR=/run/user/${TARGET_UID} /usr/bin/dockerd-rootless-setuptool.sh install"

# -- Rootless Docker -- Allow rootless Docker to bind to privileged ports (80, 443)
setcap cap_net_bind_service=ep "$(which rootlesskit)"
su - "$TARGET_USER" -c "XDG_RUNTIME_DIR=/run/user/${TARGET_UID} systemctl --user restart docker"

# -- Rootless Docker -- Set DOCKER_HOST in /etc/environment so all SSH session
# types (including non-interactive sessions used by Kamal) pick it up via PAM
echo "DOCKER_HOST=unix:///run/user/${TARGET_UID}/docker.sock" >> /etc/environment
