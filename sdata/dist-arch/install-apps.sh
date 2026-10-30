# shellcheck shell=bash
# Sourced by sdata/install/apps.sh. Arch Linux and derivatives.
#
# One metapackage; arch_install_pkgbuild already handles both repo and AUR.

have pacman || die "no pacman; sdata/dist-arch is for Arch and its derivatives"

# arch_install_paru and arch_install_pkgbuild, shared with install-deps.sh.
# Sourcing install-deps.sh to borrow them is not an option: it does its work at
# the top level, so it would re-run a full system upgrade on the way past.
# shellcheck source=sdata/lib/arch.sh
source "$REPO_ROOT/sdata/lib/arch.sh"

# local dependencies first; paru only knows the repos and the AUR
ARCH_APP_PKGBUILDS=(
    koompi-kiri
    koompi-apps
)

step "Arch: koompi-apps"
mapfile -t _koompi_pending < <(arch_pending_pkgbuilds "${ARCH_APP_PKGBUILDS[@]}")
if (( ${#_koompi_pending[@]} == 0 )); then
    ok "koompi-apps already installed and complete"
else
    # --only-apps skips the dependency step, and every browser here is an AUR build.
    arch_install_paru
    for _koompi_pkg in "${_koompi_pending[@]}"; do
        arch_install_pkgbuild "$_koompi_pkg" || return 1
    done
    unset _koompi_pkg
fi
unset _koompi_pending

# mpvpaper is the only piece of shipped configuration with no packaged home on
# any distro: switchwall.sh uses it to run a video file as the wallpaper. Every
# other wallpaper type works without it, so it is asked for rather than assumed.
if ! pacman -Qq mpvpaper >/dev/null 2>&1; then
    if confirm "Install mpvpaper? (lets you set a video as the wallpaper; AUR build)"; then
        arch_paru -S --needed --noconfirm mpvpaper
    fi
fi
