#!/bin/bash
set -ouex pipefail

# Set variables for directories we will frequently be working within
CTX_DIR=/ctx
PKG_DIR=$CTX_DIR/packages

# Copy the contents of system_files/ of the git repo to /
cp -avf "$CTX_DIR/system_files"/. /

### Modify packages
read_pkgs() {
    # 's/#.*//' drop comments, 's/^[[:space:]]*//' trim leading space, 's/[[:space:]]*$//' trim trailing space, '/^$/d' delete empty lines
    sed -e 's/#.*//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e '/^$/d' "$1"
}

# Read packages listed in build_files/packages/*
mapfile -t FEDORA_PKGS < <(read_pkgs "$PKG_DIR/install-fedora.txt")
mapfile -t TERRA_PKGS  < <(read_pkgs "$PKG_DIR/install-terra.txt") 
mapfile -t REMOVE_PKGS < <(read_pkgs "$PKG_DIR/remove.txt")

# TODO: actually modify packages