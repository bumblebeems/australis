#!/bin/bash
# Packages from Fedora's built-in repositories

PACKAGES=(
    # CLI
    bat                     # cat clone with improvements
    cdrskin                 # disc burning program
    chezmoi                 # dotfiles manager - australis handles the base system, chezmoi handles my user level config
    gh                      # github CLI
    git-delta               # delta: improved diff viewer
    eza                     # ls clone with improvements
    fd-find                 # fd: find if it didnt require a manpage to use
    nmap                    # network scanning tool
    hyfetch                 # neofetch for queers
    perl-File-Find          # required by cowsay (load bearing script very important)
    ripgrep                 # speedy grep alternative
    sbsigntools             # Includes sbverify which is needed for check-anticheat just recipe
    trash-cli               # trash for the command line
    zoxide                  # cd for lazy people

    # GUI
    gamescope               # steamos microcompositor. helps with certain games
    mangohud                # game performance overlay
    mangohud.i686           # game performance overlay (32bit)
    k3b                     # disc ripping/burning software
    kdiff3                  # diff software
    yakuake                 # quake-style dropdown terminal

    # FONTS
    ibm-plex-fonts-all      # my preferred font. nerdfonts-patched versions are not in the repos, so they're downloaded from github direct (see FONTS section in build.sh)
)

dnf5 -y install "${MULTIMEDIA_REPO_OPTS[@]}" "${PACKAGES[@]}"
