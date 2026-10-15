# shellcheck shell=bash
# Sourced by sdata/install/setups.sh. The global menu daemon: globalmenu/, Rust.

# The shell starts this binary to fill the bar's app menus (File, Edit...). It is
# the only implementation, so without cargo there is no menu at all, and setup
# says so rather than leaving the user to find an empty bar.
setup_globalmenu_rs() {
    step "Global menu daemon"
    local src="$REPO_ROOT/globalmenu"
    local build_root="$XDG_CACHE_HOME/koompi/build/globalmenu"
    local binary="$build_root/release/global-menu-daemon"
    [[ -f "$src/Cargo.toml" ]] || { warn "globalmenu source not found, skipping; the bar will show no app menus"; return 0; }
    if ! cargo_usable; then
        warn "cargo ${RUST_MIN} or newer not found: the global menu daemon is not built, so the bar shows no app menus (File, Edit...)."
        warn "Install Rust (pacman -S rust), then re-run: ./setup install --only-setups"
        return 0
    fi
    # nothing generated lands in the checkout
    ( cd "$src" && run cargo build --release --locked --target-dir "$build_root" )
    run install -Dm755 "$binary" "$XDG_BIN_HOME/koompi-global-menu-daemon"
    manifest_add "$XDG_BIN_HOME/koompi-global-menu-daemon"
    ok "koompi-global-menu-daemon installed"
}
