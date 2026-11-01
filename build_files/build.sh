#!/bin/bash

# -o pipefail: error if any part of the chain/pipeline fails | -u: throws error on unset variables | -e: exits for non-zero exit codes | -x: print all executed cmds to output
set -ouex pipefail

# =============================================================================
# SETUP
# =============================================================================

CTX_DIR=/ctx
PKG_DIR="$CTX_DIR/packages"
REMOVE_LIST="$PKG_DIR/del.txt"

# A valid line is: optional package name, optional "# comment". Blank lines are valid.
VALID_LINE='^[[:space:]]*([A-Za-z0-9._+-]+[[:space:]]*)?(#.*)?$'

# Aurora sources mesa/libva/ffmpeg from negativo17's repos; these options make sure matching pkgs in Fedora's repos aren't pulled in by accident. Also exclude steam* so it's forced to come from Terra (negativo17's otherwise replaces it via its obsoletes and priority)
MULTIMEDIA_REPO_OPTS=(--enable-repo=fedora-multimedia --setopt=fedora-multimedia.priority=90 --setopt=fedora-multimedia.excludepkgs='steam*')

# 64bit and 32bit (i686) mesa packages that must have matching versions
MESA_PKGS=(mesa-dri-drivers.x86_64 mesa-dri-drivers.i686 mesa-vulkan-drivers.x86_64 mesa-vulkan-drivers.i686)

# Blex = Plex Mono Nerd Font, pinned to a nerd-fonts release. sha256 from the GitHub release asset
BLEX_URL="https://github.com/ryanoasis/nerd-fonts/releases/download/v3.5.1/IBMPlexMono.tar.xz"
BLEX_SHA256="3d226683be9fc35f98683837568497f300307bc9b7aefc1617a368f190ef963a"

pkg_installed() {
    rpm -q "$1" >/dev/null
}

# Prepare the lists in PKG_DIR to be passed to dnf. Input is expected to be validated first! See code below "Validate all lists..." comment
parse_pkg_lists() {
    # "s/#.*//" deletes text after a #, "s/[[:space:]]//g" deletes whitespace, "/^$/d" deletes empty lines
    sed -e 's/#.*//' -e 's/[[:space:]]//g' -e '/^$/d' "$1"
}

# Copy the contents of system_files/ of the git repo to /
cp -avf "$CTX_DIR/system_files"/. /

# =============================================================================
# VALIDATE PACKAGE LISTS
# =============================================================================

# Use nullglob when defining the next two arrays so the lists created are empty in the event of no matches
shopt -s nullglob
ADD_LISTS=("$PKG_DIR"/add-*.txt)
ALL_LISTS=("$PKG_DIR"/*.txt)
shopt -u nullglob

if [[ ${#ALL_LISTS[@]} -gt 0 ]]; then
    # grep: "-v" shows lines that DON'T match, "-n" line numbers, "-H" file names. "-E" enables extended regex
    # Run from PKG_DIR with bare names (##*/ strips the directory) so output reads del.txt:5:...
    # ( ) is a subshell, so cd doesn't affect the rest of the script
    if (cd "$PKG_DIR" && grep -HnvE "$VALID_LINE" "${ALL_LISTS[@]##*/}"); then
        echo "Malformed package list(s), aborting" >&2
        exit 1
    fi
fi

# =============================================================================
# INSTALL PACKAGES
# =============================================================================

# Install each add-<repo>.txt from <repo> ("fedora" = default repos). Non-Fedora repos must already exist as .repo files
for list in "${ADD_LISTS[@]}"; do
    repo=$(basename "$list" .txt)   # /ctx/packages/add-terra.txt -> add-terra
    repo=${repo#add-}               # add-terra -> terra   (# removes a prefix)

    # convert the output of parse_pkg_lists (which will be a block of packages to install separated by newlines) into an array
    mapfile -t pkgs < <(parse_pkg_lists "$list")

    if [[ ${#pkgs[@]} -eq 0 ]]; then
        echo "$(basename "$list"): empty, skipping"
    elif [[ $repo == fedora ]]; then
        dnf5 -y install "${MULTIMEDIA_REPO_OPTS[@]}" "${pkgs[@]}"
    else
        dnf5 -y install "${MULTIMEDIA_REPO_OPTS[@]}" --from-repo="$repo" "${pkgs[@]}"
    fi
done

# =============================================================================
# REMOVE PACKAGES
# =============================================================================

REMOVE_PKGS=()
if [[ -e $REMOVE_LIST ]]; then
    mapfile -t REMOVE_PKGS < <(parse_pkg_lists "$REMOVE_LIST")
fi

# Filter out packages defined in the remove list that are not present in the base image
TO_REMOVE=()
for pkg in "${REMOVE_PKGS[@]}"; do
    if pkg_installed "$pkg"; then
        TO_REMOVE+=("$pkg")
    else
        echo "$(basename "$REMOVE_LIST"): $pkg not installed, skipping"
    fi
done

if [[ ${#TO_REMOVE[@]} -gt 0 ]]; then
    dnf5 -y remove "${TO_REMOVE[@]}"
fi

# =============================================================================
# FONTS
# =============================================================================

curl -fsSL --retry 3 -o /tmp/IBMPlexMono.tar.xz "$BLEX_URL"
echo "$BLEX_SHA256  /tmp/IBMPlexMono.tar.xz" | sha256sum -c -
mkdir -p /usr/share/fonts/blexmono-nerd
tar -xJf /tmp/IBMPlexMono.tar.xz -C /usr/share/fonts/blexmono-nerd --wildcards 'BlexMonoNerdFontMono-*.ttf' LICENSE.txt

# =============================================================================
# CHECKS
# =============================================================================

# Confirm that 32bit (i686) and 64bit mesa packages have the same version-release. A missing 32bit package also causes a failure
mapfile -t MESA_VER < <(rpm -q --qf '%{VERSION}-%{RELEASE}\n' "${MESA_PKGS[@]}" | sort -u)
if [[ ${#MESA_VER[@]} -ne 1 ]]; then
    echo "Mesa mismatch:" >&2
    # Show each package's version so the mismatch is obvious
    rpm -q --qf '%{NAME}.%{ARCH} %{VERSION}-%{RELEASE}\n' "${MESA_PKGS[@]}" >&2 || true
    exit 1
fi

# Validate that only Fedora's repos are left enabled in the image
mapfile -t ENABLED < <(dnf5 repolist --enabled | awk '$1 != "repo" {print $1}')
for enabled_repo in "${ENABLED[@]}"; do
    if [[ $enabled_repo != fedora && $enabled_repo != updates && $enabled_repo != updates-archive ]]; then
        echo "Unexpected enabled repo: $enabled_repo" >&2
        exit 1
    fi
done
