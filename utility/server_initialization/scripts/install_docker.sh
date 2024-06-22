#!/bin/bash

# -- Install Docker

# -- Install Docker -- Add the Docker keyrings
sudo apt-get update
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# -- Install Docker -- Add the repository to Apt sources
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update

# -- Install the Docker packages
sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin


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

# -- Bind rootless Docker to priviliged ports
sudo setcap cap_net_bind_service=ep $(which rootlesskit)
systemctl --user restart docker

sed -i '$a\
\
\
# -- Docker Environment Variables\
\
export PATH=/usr/bin:$PATH\
export DOCKER_HOST=unix:///run/user/1000/docker.sock' ~/.bashrc
