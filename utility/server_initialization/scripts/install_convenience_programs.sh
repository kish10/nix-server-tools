#!/bin/bash


# -- Install Neovim


# -- -- Install the binary

curl -LO https://github.com/neovim/neovim/releases/latest/download/nvim-linux64.tar.gz
sudo rm -rf /opt/nvim
sudo tar -C /opt -xzf nvim-linux64.tar.gz
rm nvim-linux64.tar.gz


# -- -- Add Neovim to the path

sed -i '$a\
\
\
# -- Neovim configuration\
\
export PATH="$PATH:/opt/nvim-linux64/bin"\
alias vim="neovim"' ~/.bashrc

source ~/.bashrc
