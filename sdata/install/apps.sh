# shellcheck shell=bash
# Sourced by ./setup. Runs the Arch application recipe.
#
# Separate from deps.sh on purpose: that step installs what the session cannot start
# without, this one the programs KOOMPI has an opinion about. --no-apps leaves a
# working desktop with whatever applications were already there.

# Named for the confirmation prompt, so someone who has never read this repo
# still knows what is about to land on their disk.
readonly APPS_SUMMARY='KOOMPI Workbench (Claude Code, Codex, Pi, Herdr, Neovim),
  wezterm, konsole, zed, chrome, brave, dolphin extras, okular, loupe, mpv,
  libreoffice, btop, kdeconnect and a modern command-line toolkit'

install_apps() {
    step "Installing applications"

    local recipe="$REPO_ROOT/sdata/dist-arch/install-apps.sh"
    [[ -f "$recipe" ]] || die "missing recipe: $recipe"

    # Several gigabytes, two proprietary browsers and an office suite - the right
    # default for a KOOMPI machine, the wrong thing to do silently to someone trying the
    # shell out. Only asked when the set is not already present, so nobody is asked
    # twice. The recipe runs either way and skips what is there, which is how
    # applications added upstream since the last run get picked up.
    local cmd missing=0
    for cmd in "${APP_CMDS[@]}" "${AGENT_CMDS[@]}"; do
        have "$cmd" || missing=$((missing + 1))
    done

    if (( missing == 0 )); then
        ok "the KOOMPI application set is already present; checking for additions"
    else
        printf '\n  The KOOMPI application set:\n  %s\n\n' "$APPS_SUMMARY"
        if ! confirm "Install these? (no = keep the applications you already have)"; then
            warn "skipped; the desktop works, but keybinds fall back to whatever is on PATH"
            return 0
        fi
    fi

    info "using $recipe"
    # same as deps.sh: a recipe that bailed must not fall through to "ok"
    # shellcheck source=/dev/null
    source "$recipe" || { err "the Arch application recipe failed"; return 1; }

    # Agent CLIs update too quickly for distro archives. They are installed
    # user-locally from their official distribution channels after the distro
    # recipe has supplied Node/npm and the native CLI foundation.
    # shellcheck source=sdata/install/agents.sh
    source "$REPO_ROOT/sdata/install/agents.sh"
    install_agent_tools

    ok "applications installed"
}
