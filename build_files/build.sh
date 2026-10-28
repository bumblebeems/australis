#!/bin/bash

set -ouex pipefail

# Copy the contents of system_files/ of the git repo to /
cp -avf "/ctx/system_files"/. /

### Modify packages
PKG_DIR=/ctx/packages

read_pkgs() {
    # 's/#.*//' drop comments, 's/^[[:space:]]*//' trim leading space, 's/[[:space:]]*$//' trim trailing space, '/^$/d' delete empty lines
    sed -e 's/#.*//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e '/^$/d' "$1"
}

# Install packages from build_files/packages/install-fedora.txt
mapfile -t FEDORA_PKGS < <(read_pkgs "$PKG_DIR/install-fedora.txt")

# Install packages from build_files/packages/install-terra.txt
mapfile -t TERRA_PKGS  < <(read_pkgs "$PKG_DIR/install-terra.txt")

# Remove unwanted packages from base image
mapfile -t REMOVE_PKGS < <(read_pkgs "$PKG_DIR/remove.txt")

# TODO: actually modify packages