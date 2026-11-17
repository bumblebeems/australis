#!/bin/bash

# -o pipefail: error if any part of the chain/pipeline fails | -u: throws error on unset variables | -e: exits for non-zero exit codes | -x: print all executed cmds to output
set -ouex pipefail

# =============================================================================
# SETUP
# =============================================================================

# Image identity used for os-release and image-info.json
IMG_NAME="Australis"
IMG_NAME_LOWER="${IMG_NAME,,}"
IMG_VENDOR="bumblebeems"
IMG_REPO="https://github.com/$IMG_VENDOR/$IMG_NAME_LOWER"
IMG_GHCR="ghcr.io/$IMG_VENDOR/$IMG_NAME_LOWER"
IMG_TAG='latest'

# Source directory
CTX_DIR=/ctx

# Flatpak preinstall directory
FPK_PREINSTALL_DIR=/usr/share/flatpak/preinstall.d

# Aurora sources mesa/libva/ffmpeg from negativo17's repos; these options make sure matching pkgs in Fedora's repos aren't pulled in by accident. Also exclude steam* so it's forced to come from Terra (negativo17's otherwise replaces it via its obsoletes and priority)
MULTIMEDIA_REPO_OPTS=(--enable-repo=fedora-multimedia --setopt=fedora-multimedia.priority=90 --setopt=fedora-multimedia.excludepkgs='steam*')

# 64bit and 32bit (i686) mesa packages that must have matching versions
MESA_PKGS=(mesa-dri-drivers.x86_64 mesa-dri-drivers.i686 mesa-vulkan-drivers.x86_64 mesa-vulkan-drivers.i686)

# Blex = Plex Mono Nerd Font, pinned to a nerd-fonts release. sha256 from the GitHub release asset
FONT_BLEX_URL="https://github.com/ryanoasis/nerd-fonts/releases/download/v3.5.1/IBMPlexMono.tar.xz"
FONT_BLEX_SHA="3d226683be9fc35f98683837568497f300307bc9b7aefc1617a368f190ef963a"

# =============================================================================
# COPY SYSTEM_FILES/* INTO IMAGE
# =============================================================================

# Copy the contents of system_files/ of the git repo to /
cp -avf "$CTX_DIR/system_files"/. /

# =============================================================================
# UJUST RECIPE OVERRIDES
# =============================================================================

# Append recipes in overrides.just to 00-entry.just. Top-level recipes override imported ones, but between imports the EARLIER one wins, so an imported override file doesn't work
echo >> /usr/share/ublue-os/just/00-entry.just
cat "$CTX_DIR/overrides.just" >> /usr/share/ublue-os/just/00-entry.just

# =============================================================================
# EXECUTE PACKAGE SCRIPTS
# =============================================================================

# Run scripts in build_files/rpm/
shopt -s nullglob
for script in "$CTX_DIR"/rpm/*.sh; do
    ( source "$script" )
done
shopt -u nullglob

mkdir -p "$FPK_PREINSTALL_DIR"

# Run scripts in build_files/flatpak/
shopt -s nullglob
for script in "$CTX_DIR"/flatpak/*.sh; do
    ( source "$script" )
done
shopt -u nullglob

# =============================================================================
# TWEAK BRANDING
# =============================================================================

IMG_INFO=/usr/share/ublue-os/image-info.json

# ublue images ship with image-info.json which scripts and ujust recipes read to know which image they're on
jq --arg name "$IMG_NAME_LOWER" --arg vendor "$IMG_VENDOR" --arg tag "$IMG_TAG" --arg repo "$IMG_GHCR" '
    .["image-name"] = $name
    | .["image-vendor"] = $vendor
    | .["image-tag"] = $tag
    | .["image-ref"] |= sub("ghcr\\.io/.*$"; $repo)
' "$IMG_INFO" > /tmp/image-info.json
cp /tmp/image-info.json "$IMG_INFO"

OS_RELEASE=/usr/lib/os-release

set_os_release() {
    # Replace KEY="..." if present, otherwise add it
    if grep -q "^$1=" "$OS_RELEASE"; then
        sed -i "s|^$1=.*|$1=\"$2\"|" "$OS_RELEASE"
    else
        echo "$1=\"$2\"" >> "$OS_RELEASE"
    fi
}

get_os_release() {
    if grep -q "^$1=" "$OS_RELEASE"; then
        sed -n "s|^$1=||p" "$OS_RELEASE" | sed -E 's/^"(.*)"$/\1/; s/^'\''(.*)'\''$/\1/'
    else
        return 1
    fi
}

shopt -s inherit_errexit
IMG_VER=$(get_os_release IMAGE_VERSION)
AURORA_BUILD_ID=$(get_os_release BUILD_ID)
shopt -u inherit_errexit

set_os_release NAME "$IMG_NAME"
set_os_release PRETTY_NAME "$IMG_NAME (Version: $IMG_VER)"
set_os_release DEFAULT_HOSTNAME "$IMG_NAME_LOWER"
set_os_release HOME_URL "$IMG_REPO"
set_os_release SUPPORT_URL "$IMG_REPO/issues"
set_os_release BUG_REPORT_URL "$IMG_REPO/issues"
set_os_release BUILD_ID "$COMMIT_SHA"
set_os_release IMAGE_ID "$IMG_NAME_LOWER"
set_os_release AURORA_BUILD_ID "$AURORA_BUILD_ID"

# Modify kinfocenter branding ("Variant" is blank as by default Aurora adds "Kinoite")
cat > /usr/share/kde-settings/kde-profile/default/xdg/kcm-about-distrorc <<EOF
[General]
LogoPath=/usr/share/pixmaps/system-logo.png
Name=$IMG_NAME
Version=$IMG_VER
Variant=
Website=$IMG_REPO
EOF

# =============================================================================
# ENFORCE SIGNED IMAGES
# =============================================================================

# Require australis images to be signed with our cosign key before existing installs will accept updates
POLICY=/etc/containers/policy.json
jq --arg repo "$IMG_GHCR" --arg name "$IMG_NAME_LOWER" '
    .transports.docker[$repo] = [{
        "type": "sigstoreSigned",
        "keyPaths": ["/usr/lib/pki/containers/" + $name + ".pub"],
        "signedIdentity": {"type": "matchRepository"}
    }]
' "$POLICY" > /tmp/policy.json
cp /tmp/policy.json "$POLICY"

# =============================================================================
# INSTALL ADDITIONAL FONTS
# =============================================================================

curl -fsSL --retry 3 -o /tmp/IBMPlexMono.tar.xz "$FONT_BLEX_URL"
echo "$FONT_BLEX_SHA  /tmp/IBMPlexMono.tar.xz" | sha256sum -c -
mkdir -p /usr/share/fonts/blexmono-nerd
tar -xJf /tmp/IBMPlexMono.tar.xz -C /usr/share/fonts/blexmono-nerd --wildcards 'BlexMonoNerdFontMono-*.ttf' LICENSE.txt
fc-cache -f /usr/share/fonts/blexmono-nerd

# =============================================================================
# CLEANUP AND PRUNING
# =============================================================================

# Remove alias of fastfetch -> ublue-fastfetch
rm -f /usr/share/fish/vendor_conf.d/ublue-fastfetch.fish
rm -f /etc/profile.d/ublue-fastfetch.sh

# Remove "Aurora Preferences" page from KDE systemsettings (everything except toggle autoupdate is broken on/will break Australis)
rm -f /usr/share/applications/kcm_ublue.desktop
rm -f /usr/lib64/qt6/plugins/plasma/kcms/systemsettings/kcm_ublue.so

# Hide gcdmaster from applications list (its built into cdrdao but we prefer k3b)
if [[ -f /usr/share/applications/gcdmaster.desktop ]]; then
    echo "NoDisplay=true" >> /usr/share/applications/gcdmaster.desktop
fi

# =============================================================================
# CHECK IF WE BROKE SHIT
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

# Validate that policy.json has our signing rule (otherwise unsigned images would be accepted)
if ! jq -e --arg repo "$IMG_GHCR" '.transports.docker[$repo][0].type == "sigstoreSigned"' "$POLICY" >/dev/null; then
    echo "Signature policy rule for $IMG_GHCR missing from $POLICY" >&2
    exit 1
fi
