# shellcheck shell=bash
# Sourced by ./setup. Runs the Arch recipe; setup has already refused anything else.
#
# sdata/dist-arch/install-deps.sh is sourced, not executed, so it can use
# run/info/warn and see REPO_ROOT and the OS_* variables. It must leave the system
# usable if it bails.

install_deps() {
    step "Installing dependencies"

    local recipe="$REPO_ROOT/sdata/dist-arch/install-deps.sh"
    [[ -f "$recipe" ]] || die "missing recipe: $recipe"

    info "using $recipe"
    # The status matters. A recipe that bailed used to fall through to the success
    # message below, so a run could print "aborted" and "ok dependencies installed"
    # three lines apart and carry on against packages that were never built.
    # shellcheck source=/dev/null
    source "$recipe" || { err "the Arch dependency recipe failed"; return 1; }

    ok "dependencies installed"
}
