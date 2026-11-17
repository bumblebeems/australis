#!/bin/bash
# https://github.com/terrapkg/packages

REPO=terra

PACKAGES=(
    amdgpu_top          # monitor for radeon GPUs
    bitwarden-cli       # cli password manager
    steam               # video games
    starship            # shell prompt
)

dnf5 -y install "${MULTIMEDIA_REPO_OPTS[@]}" --from-repo="$REPO" "${PACKAGES[@]}"
