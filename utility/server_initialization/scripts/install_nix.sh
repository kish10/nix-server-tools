#!/bin/bash

# -- Install Nix
yes | sh <(curl -L https://nixos.org/nix/install) --daemon

# -- Enable flakes
sed -i '$a\
\
\
# -- Enable flakes\
\
experimental-features = nix-command flakes' /etc/nix/nix.conf
