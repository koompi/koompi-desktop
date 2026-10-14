# shellcheck shell=bash
# Sourced by ./setup. KOOMPI Desktop installs on Arch Linux and the distributions built
# on it (EndeavourOS, CachyOS, Manjaro, KOOMPI OS), which reach the arch group through
# ID_LIKE. Anything else is refused up front: the desktop is built, packaged and tested
# on Arch only, and a half-working install on another distro is worse than none.

detect_distro() {
    local os_release=/etc/os-release
    # Lets CI and `setup checkdeps` pretend to be another distro.
    [[ -n "${KOOMPI_OS_RELEASE:-}" ]] && os_release="${KOOMPI_OS_RELEASE}"
    [[ -r "$os_release" ]] || die "cannot read $os_release, so the distro cannot be identified"

    OS_DISTRO_ID="$(awk -F= '/^ID=/        { gsub(/["\047]/,"",$2); print tolower($2); exit }' "$os_release")"
    OS_DISTRO_LIKE="$(awk -F= '/^ID_LIKE=/ { gsub(/["\047]/,"",$2); print tolower($2); exit }' "$os_release")"
    OS_VERSION_ID="$(awk -F= '/^VERSION_ID=/ { gsub(/["\047]/,"",$2); print $2; exit }' "$os_release")"
    OS_PRETTY_NAME="$(awk -F= '/^PRETTY_NAME=/ { gsub(/["\047]/,"",$2); print $2; exit }' "$os_release")"
    export OS_DISTRO_ID OS_DISTRO_LIKE OS_VERSION_ID OS_PRETTY_NAME

    OS_GROUP_ID=''
    OS_GROUP_EXACT=true
    local id
    for id in "$OS_DISTRO_ID" $OS_DISTRO_LIKE; do
        case "$id" in
            arch|archlinux|koompi) OS_GROUP_ID=arch ;;
            *)                     continue ;;
        esac
        [[ "$id" == "$OS_DISTRO_ID" ]] || OS_GROUP_EXACT=false
        break
    done
    export OS_GROUP_ID OS_GROUP_EXACT

    OS_ARCH="$(uname -m)"
    export OS_ARCH
}

report_distro() {
    info "distro: ${OS_DISTRO_ID:-unknown} ${OS_VERSION_ID:-} (ID_LIKE: ${OS_DISTRO_LIKE:-none})"
    info "arch:   ${OS_ARCH}"
    if [[ "$OS_GROUP_ID" != arch ]]; then
        warn "KOOMPI Desktop runs on Arch Linux and Arch-based distributions only"
        warn "(EndeavourOS, CachyOS, Manjaro, KOOMPI OS). This is ${OS_PRETTY_NAME:-${OS_DISTRO_ID:-an unknown system}}."
        return 1
    fi
    info "package recipe: sdata/dist-arch"
    if [[ "$OS_GROUP_EXACT" != true ]]; then
        info "an Arch-based distribution (via ID_LIKE); its own repositories may lag Arch's"
    fi
    if [[ "$OS_ARCH" != x86_64 ]]; then
        warn "only x86_64 is tested; expect missing packages on ${OS_ARCH}."
    fi
    return 0
}

# install and update stop here on anything that is not Arch
require_arch() {
    report_distro || die "nothing was changed. Install Arch Linux, or an Arch-based distribution, and run this again"
}
