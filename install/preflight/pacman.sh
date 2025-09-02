#!/bin/bash

# Install build tools
sudo pacman -S --needed --noconfirm base-devel

# Configure pacman
sudo cp -f ~/.local/share/omarchy/default/pacman/pacman.conf /etc/pacman.conf

# Use ARM-specific mirrorlist on ARM systems
if [[ "$OMARCHY_ARM" == "true" ]]; then
  sudo cp -f ~/.local/share/omarchy/default/pacman/mirrorlist.arm /etc/pacman.d/mirrorlist
else
  sudo cp -f ~/.local/share/omarchy/default/pacman/mirrorlist /etc/pacman.d/mirrorlist
fi

# Refresh all repos
sudo pacman -Syu --noconfirm
