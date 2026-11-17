#!/bin/bash

PACKAGES=(
    mariadb                 # leftover from akonadi, which aurora already removes
    mariadb-server
    kate                    # I prefer kwrite or nano for text/quick edits and vscode for larger projects
    kate-plugins
    kate-krunner-plugin
)

TO_REMOVE=()
for pkg in "${PACKAGES[@]}"; do
    if rpm -q "$pkg" &>/dev/null; then
        TO_REMOVE+=("$pkg")
    else
        echo "remove: $pkg not installed, skipping"
    fi
done

if [[ ${#TO_REMOVE[@]} -gt 0 ]]; then
    dnf5 -y remove "${TO_REMOVE[@]}"
fi
