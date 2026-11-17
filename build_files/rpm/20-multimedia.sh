#!/bin/bash
# Packages from Negativo17's multimedia repo

REPO=fedora-multimedia 

PACKAGES=(
    libheif.i686    # Dependency pulled in when installing steam, but if I don't explicitly install it from this repo dnf picks from Fedora's default repos and downgrades the existing 64bit lib
    openh264        # real H.264 codec (replaces Fedora's noopenh264 stub)
    openh264.i686   # 32bit version of the above
)

dnf5 -y install "${MULTIMEDIA_REPO_OPTS[@]}" --from-repo="$REPO" "${PACKAGES[@]}"
