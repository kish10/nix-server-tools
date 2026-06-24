#!/bin/bash

# -- Install Docker

# -- Install Docker -- Add the Docker keyrings
sudo apt-get update
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# -- Install Docker -- Add the repository to Apt sources
#
# Uses UBUNTU_CODENAME with fallback to VERSION_CODENAME — per Docker's current
# install docs. UBUNTU_CODENAME is more reliable on new Ubuntu releases where
# the Docker repo may not yet have a matching entry for VERSION_CODENAME.
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update

# -- Install the Docker packages
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin


# -- Install rootless prerequisites

sudo sh -eux <<EOF
# Install newuidmap & newgidmap binaries
apt-get install -y uidmap
EOF


# -- Install rootless Docker

# -- Stop Docker daemon
sudo systemctl disable --now docker.service docker.socket

# -- Install rootless Docker -- Install
/usr/bin/dockerd-rootless-setuptool.sh install

# -- Bind rootless Docker to privileged ports
sudo setcap cap_net_bind_service=ep $(which rootlesskit)
systemctl --user restart docker

# -- Enable Docker to start at boot without the user being logged in
#
# Required for production — without linger, the rootless Docker daemon only
# runs while this user has an active session. On server reboot, Docker won't
# start until someone logs in.
sudo loginctl enable-linger "$(whoami)"

# -- Set Docker environment variables
#
# Written to /etc/environment (loaded by PAM for all session types) rather
# than ~/.bashrc (interactive shells only). This ensures DOCKER_HOST is
# available in non-interactive SSH sessions used by tools like Kamal.
DEPLOY_UID=$(id -u)
sudo tee -a /etc/environment > /dev/null <<EOF

# Docker rootless socket
DOCKER_HOST=unix:///run/user/${DEPLOY_UID}/docker.sock
EOF

export PATH=/usr/bin:$PATH
export DOCKER_HOST=unix:///run/user/${DEPLOY_UID}/docker.sock
