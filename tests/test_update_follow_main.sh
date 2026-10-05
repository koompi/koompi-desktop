#!/usr/bin/env bash
# Installed machines follow main. They used to follow prod-hd, a release line
# fast-forwarded from main that is being retired: `koompi update` moves a
# managed checkout off it, and a re-run of the one-liner repairs one, so both
# keep working once prod-hd is deleted upstream. Every other checkout - a dev's,
# a fork's, one with work in it - has to come out exactly as it went in.
# Every bare global assigned below is one ./setup sets and the sourced update.sh
# reads - REPO_ROOT, DRY_RUN, ASSUME_YES, DO_*, SKIP_BACKUP - so SC2034 fires on
# all of them by design; nothing in this file reads them itself.
# shellcheck disable=SC2034
# shellcheck source-path=SCRIPTDIR
set -uo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
pass() { printf 'PASS: %s\n' "$1"; }
command -v git >/dev/null || { echo "git not installed; skipping" >&2; exit 0; }

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

export HOME="$T/home"
export NO_COLOR=1
mkdir -p "$HOME"
cat > "$HOME/.gitconfig" <<'GITCONFIG'
[user]
	name = koompi test
	email = test@koompi
[init]
	defaultBranch = main
[advice]
	detachedHead = false
	diverging = false
GITCONFIG

DRY_RUN=false
ASSUME_YES=false
# shellcheck source=../sdata/lib/common.sh disable=SC1091
source "$ROOT/sdata/lib/common.sh"
# Reassigned per case below; update.sh reads it at source time.
REPO_ROOT="$T"
# shellcheck source=../sdata/install/update.sh disable=SC1091
source "$ROOT/sdata/install/update.sh"
RETIRED=prod-hd

# An origin under a koompi/koompi-desktop path so the "is this the KOOMPI repo?"
# check sees what it sees on a real machine. prod-hd sits one commit behind
# main: the state the field is in.
new_origin() {
    local dir="$1" origin="$1/koompi/koompi-desktop.git" seed="$1/seed"
    mkdir -p "$dir/koompi"
    git init -q --bare "$origin"
    git clone -q "$origin" "$seed" 2>/dev/null
    echo v1 > "$seed/file"; git -C "$seed" add .; git -C "$seed" commit -qm v1
    git -C "$seed" push -q origin HEAD:main HEAD:"refs/heads/$RETIRED"
    echo v2 > "$seed/file"; git -C "$seed" add .; git -C "$seed" commit -qm v2
    git -C "$seed" push -q origin HEAD:main
    printf '%s\n' "$origin"
}
seed_of()      { printf '%s/seed\n' "${1%/koompi/koompi-desktop.git}"; }
advance_main() {
    local seed; seed="$(seed_of "$1")"
    echo "v$RANDOM" > "$seed/file"; git -C "$seed" commit -qam next
    git -C "$seed" push -q origin HEAD:main
}
retire()       { git -C "$(seed_of "$1")" push -q origin --delete "$RETIRED"; }

branch_of()   { git -C "$1" rev-parse --abbrev-ref HEAD; }
head_of()     { git -C "$1" rev-parse HEAD; }
upstream_of() { git -C "$1" rev-parse --abbrev-ref '@{u}' 2>/dev/null; }
remote_head() { git -C "$1" ls-remote --heads origin "$2" | cut -f1; }
on_retired()  { git clone -q --branch "$RETIRED" "$1" "$2"; }
# update_pull sets PULL_MOVED; a command substitution would run it in a subshell
# and lose it, so the cases that read it capture through a file instead.
do_pull() { update_pull < /dev/null > "$T/pull.out" 2>&1; out="$(cat "$T/pull.out")"; }

origin="$(new_origin "$T/a")"

# --- a managed checkout on prod-hd moves to main ------------------------------
work="$T/a/managed"
on_retired "$origin" "$work"
REPO_ROOT="$work"
out="$(update_pull < /dev/null 2>&1)"
[[ "$(branch_of "$work")" == main ]] || fail "a managed $RETIRED checkout did not move to main: $out"
[[ "$(upstream_of "$work")" == origin/main ]] \
    || fail "the moved branch does not track origin/main: $(upstream_of "$work")"
[[ "$(head_of "$work")" == "$(remote_head "$work" main)" ]] \
    || fail "the moved checkout is not at origin/main: $out"
grep -q "moved from '$RETIRED' to main" <<<"$out" || fail "the move was not reported: $out"
git -C "$work" rev-parse --verify --quiet "refs/heads/$RETIRED" >/dev/null \
    && fail "the local $RETIRED was left behind"
pass "a managed checkout on $RETIRED moves to main"

# --- and keeps pulling once prod-hd is gone upstream --------------------------
retire "$origin"; advance_main "$origin"
out="$(update_pull < /dev/null 2>&1)"
grep -q 'updated ' <<<"$out" || fail "the moved checkout did not pull after $RETIRED was deleted: $out"
[[ "$(head_of "$work")" == "$(remote_head "$work" main)" ]] || fail "the pull did not land on main: $out"
pass "the moved checkout keeps pulling after $RETIRED is deleted"

# --- the shape install.sh used to leave: shallow, single-branch prod-hd -------
origin="$(new_origin "$T/c")"
work="$T/c/shallow"
git clone -q --depth 1 --branch "$RETIRED" "file://$origin" "$work" 2>/dev/null
REPO_ROOT="$work"
out="$(update_pull < /dev/null 2>&1)"
[[ "$(branch_of "$work")" == main ]] || fail "a shallow single-branch $RETIRED checkout did not move: $out"
retire "$origin"; advance_main "$origin"
out="$(update_pull < /dev/null 2>&1)"
grep -q 'updated ' <<<"$out" || fail "the shallow checkout did not pull after $RETIRED was deleted: $out"
pass "a shallow single-branch $RETIRED checkout moves and keeps pulling"

# --- a checkout already on main drops a leftover prod-hd refspec --------------
origin="$(new_origin "$T/b")"
work="$T/b/main-refspec"
git clone -q "$origin" "$work"
git -C "$work" config --add remote.origin.fetch "+refs/heads/$RETIRED:refs/remotes/origin/$RETIRED"
retire "$origin"; advance_main "$origin"
REPO_ROOT="$work"
out="$(update_pull < /dev/null 2>&1)"
grep -q 'updated ' <<<"$out" || fail "a main checkout with a $RETIRED refspec did not pull: $out"
git -C "$work" config --get-all remote.origin.fetch | grep -q "$RETIRED" \
    && fail "the $RETIRED refspec was left in place"
grep -qE 'moved from|warn|error|fatal' <<<"$out" && fail "an ordinary main update reported a move or a failure: $out"
pass "a main checkout drops a leftover $RETIRED refspec and pulls"

work="$T/b/main-refspec-dry"
git clone -q "$origin" "$work"
git -C "$work" config --add remote.origin.fetch "+refs/heads/$RETIRED:refs/remotes/origin/$RETIRED"
REPO_ROOT="$work"
DRY_RUN=true
out="$(update_pull < /dev/null 2>&1)"
DRY_RUN=false
git -C "$work" config --get-all remote.origin.fetch | grep -q "$RETIRED" \
    || fail "a dry run rewrote the fetch refspecs: $out"
pass "a dry run leaves a leftover $RETIRED refspec in place"

origin="$(new_origin "$T/a2")"

# --- a prod-hd checkout with a commit of its own is not touched ---------------
work="$T/a2/local-commit"
on_retired "$origin" "$work"
echo mine > "$work/mine"; git -C "$work" add .; git -C "$work" commit -qm mine
REPO_ROOT="$work"
before="$(head_of "$work")"
out="$(printf 'a\n' | update_pull 2>&1)"
[[ "$(branch_of "$work")" == "$RETIRED" ]] || fail "a checkout with a local commit was moved: $out"
[[ "$(head_of "$work")" == "$before" ]] || fail "a checkout with a local commit moved its HEAD: $out"
grep -q 'commits main does not have' <<<"$out" || fail "no reason was given: $out"
pass "a $RETIRED checkout carrying its own commit is left alone"

# --- a local main of somebody's own is not reset ------------------------------
work="$T/a2/own-main"
git clone -q "$origin" "$work"
echo mine > "$work/mine"; git -C "$work" add .; git -C "$work" commit -qm "my main"
mine="$(head_of "$work")"
git -C "$work" checkout -q -b "$RETIRED" --track "origin/$RETIRED"
REPO_ROOT="$work"
out="$(update_pull < /dev/null 2>&1)"
[[ "$(branch_of "$work")" == "$RETIRED" ]] || fail "a checkout whose local main is its own was moved: $out"
[[ "$(git -C "$work" rev-parse main)" == "$mine" ]] || fail "a local main with its own commit was reset"
grep -q "local 'main' here carries commits" <<<"$out" || fail "no reason was given: $out"
pass "a local main with commits of its own is not reset"

# --- a dirty tree is not touched ----------------------------------------------
work="$T/a2/dirty"
on_retired "$origin" "$work"
echo edited >> "$work/file"
REPO_ROOT="$work"
before="$(head_of "$work")"
out="$(update_pull < /dev/null 2>&1)"
[[ "$(branch_of "$work")" == "$RETIRED" ]] || fail "a dirty checkout was moved: $out"
[[ "$(head_of "$work")" == "$before" ]] || fail "a dirty checkout moved its HEAD: $out"
[[ "$(cat "$work/file")" == "v1
edited" ]] || fail "a dirty checkout lost its edit: $(cat "$work/file")"
grep -q 'uncommitted changes' <<<"$out" || fail "no reason was given: $out"
pass "a dirty checkout is left alone"

# --- a developer's own branch is not touched ----------------------------------
work="$T/a2/feature"
git clone -q "$origin" "$work"
git -C "$work" checkout -q -b feature
git -C "$work" push -q -u origin feature 2>/dev/null
REPO_ROOT="$work"
out="$(update_pull < /dev/null 2>&1)"
[[ "$(branch_of "$work")" == feature ]] || fail "a developer's branch was hijacked: $out"
grep -q 'moved from' <<<"$out" && fail "a developer's branch was reported moved: $out"
pass "a feature branch is left alone"

# --- a fork or a mirror is not touched ----------------------------------------
mkdir -p "$T/a2/someone"
git clone -q --bare "$origin" "$T/a2/someone/koompi-desktop.git" 2>/dev/null
work="$T/a2/fork"
on_retired "$T/a2/someone/koompi-desktop.git" "$work"
REPO_ROOT="$work"
out="$(update_pull < /dev/null 2>&1)"
[[ "$(branch_of "$work")" == "$RETIRED" ]] || fail "a fork was moved onto main: $out"
grep -q 'not the KOOMPI repo' <<<"$out" || fail "no reason was given: $out"
pass "a checkout whose origin is not the KOOMPI repo is left alone"

# --- a dry run moves nothing ---------------------------------------------------
work="$T/a2/dryrun"
on_retired "$origin" "$work"
REPO_ROOT="$work"
before="$(head_of "$work")"
DRY_RUN=true
out="$(update_pull < /dev/null 2>&1)"
DRY_RUN=false
[[ "$(branch_of "$work")" == "$RETIRED" ]] || fail "a dry run switched the branch: $out"
[[ "$(head_of "$work")" == "$before" ]] || fail "a dry run moved HEAD: $out"
grep -q 'dry run' <<<"$out" || fail "the dry run did not say what it would do: $out"
pass "a dry run moves nothing"

# --- every origin generation a real machine can carry counts as ours ----------
# The repo was renamed twice on 2026-08-26: koompi/desktop, then the one-day
# koompi-hd spelling, then koompi-desktop. A false negative here would leave a
# machine stranded on the retired branch.
gen="$T/a2/generations"
git init -q "$gen"
gh="git@github.com" https="https://github.com" org="koompi"
hdslug="koompi-hd"
cur="koompi-desktop"
for url in \
    "$gh:$org/desktop.git" \
    "$https/$org/desktop" \
    "$https/$org/desktop/" \
    "$gh:$org/$hdslug.git" \
    "$https/$org/$hdslug" \
    "$https/$org/$cur.git" \
    "$https/$org/$cur/"; do
    git -C "$gen" remote remove origin 2>/dev/null
    git -C "$gen" remote add origin "$url"
    REPO_ROOT="$gen"
    origin_is_koompi || fail "an origin at $url was disowned"
done
pass "every origin generation a real machine can have is still the KOOMPI repo"


# --- an update must run the code it just pulled, not the code it started with --
# J49 F1: bash parsed every installer function before the pull, so the sysctl fix
# took two consecutive updates to take effect on a real machine.
mkdir -p "$T/d/koompi"
reexec_origin="$T/d/koompi/koompi-desktop.git"
git init -q --bare "$reexec_origin"
git clone -q "$reexec_origin" "$T/d/seed" 2>/dev/null
seed="$T/d/seed"
write_setup() {
    cat > "$seed/setup" <<SETUP
#!/usr/bin/env bash
printf 'setup v%s ran: %s\n' "$1" "\$*"
printf 'REEXEC=%s PRE=%s\n' "\${KOOMPI_UPDATE_REEXEC:-}" "\${KOOMPI_UPDATE_PRE_DEFAULTS:-}"
SETUP
    chmod +x "$seed/setup"
    git -C "$seed" add setup
    git -C "$seed" commit -qm "setup v$1"
    git -C "$seed" push -q origin HEAD:main
}
write_setup 1
work="$T/d/machine"
git clone -q "$reexec_origin" "$work"
write_setup 2
REPO_ROOT="$work"
DO_DEPS=false; DO_APPS=true; DO_SETUPS=true; DO_FILES=true; SKIP_BACKUP=false
ASSUME_YES=true
do_pull
grep -q 'updated ' <<<"$out" || fail "the re-exec fixture did not pull: $out"
[[ "$PULL_MOVED" == true ]] || fail "a pull that moved HEAD did not set PULL_MOVED: $out"
out="$(rerun_from_pulled_tree /tmp/koompi-pre-fixture 2>&1)"
grep -q 'setup v2 ran' <<<"$out" \
    || fail "the update did not re-run the setup it had just pulled: $out"
grep -q 'setup v2 ran: update --no-deps --yes' <<<"$out" \
    || fail "the re-exec did not carry the options this run was given: $out"
grep -q 'REEXEC=1 PRE=/tmp/koompi-pre-fixture' <<<"$out" \
    || fail "the re-exec lost the guard or the pre-pull defaults dump: $out"
pass "an update re-runs the installer code it just pulled"

# --- and does it at most once, whatever happens -------------------------------
out="$(export KOOMPI_UPDATE_REEXEC=1; rerun_from_pulled_tree "" 2>&1)"
grep -q 'setup v2 ran' <<<"$out" && fail "the re-exec guard did not hold: $out"
grep -q 'already loaded' <<<"$out" || fail "the second pass said nothing: $out"
pass "the re-exec happens at most once"

# --- a run that pulled nothing does not re-exec -------------------------------
do_pull
[[ "$PULL_MOVED" == false ]] || fail "a no-op pull claimed HEAD moved: $out"
out="$(rerun_from_pulled_tree "" 2>&1)"
grep -q 'setup v2 ran' <<<"$out" && fail "an update with nothing to pull re-executed: $out"
pass "an update that pulled nothing runs straight through"

# --- run_update still calls it, and after the pull ----------------------------
body="$(sed -n '/^run_update()/,/^}/p' "$ROOT/sdata/install/update.sh")"
l_pull="$(grep -n '^    update_pull$' <<<"$body" | cut -d: -f1)"
l_again="$(grep -n 'rerun_from_pulled_tree' <<<"$body" | cut -d: -f1)"
[[ -n "$l_pull" && -n "$l_again" ]] || fail "run_update no longer pulls and re-runs: $body"
(( l_pull < l_again )) || fail "the re-exec is not after the pull (lines $l_pull, $l_again)"
pass "run_update re-runs from the pulled tree, after the pull"

# --- the rebuilt argv cannot silently drop an option setup grows --------------
# run_update never sees argv, so the re-exec rebuilds it from the parsed flags.
mapfile -t setup_opts < <(sed -n '/^parse_install_options()/,/^}/p' "$ROOT/setup" \
    | grep -oE -- '--[a-z-]+' | sort -u)
(( ${#setup_opts[@]} > 5 )) || fail "could not read setup's options: ${setup_opts[*]}"
rebuild="$(sed -n '/^rerun_from_pulled_tree()/,/^}/p' "$ROOT/sdata/install/update.sh")"
# --only-* is exactly the matching set of --no-*, and --help is not a state
ignored=' --only-deps --only-apps --only-setups --only-files --help '
for opt in "${setup_opts[@]}"; do
    [[ "$ignored" == *" $opt "* ]] && continue
    grep -qF -- "$opt" <<<"$rebuild" \
        || fail "./setup update takes $opt but the re-exec would drop it"
done
pass "every option setup takes survives the re-exec"

# --- install.sh follows main --------------------------------------------------
INSTALL="$ROOT/install.sh"
install_into() {
    local url="$1" dest="$2"; shift 2
    ( cd "$T" && env "$@" KOOMPI_REPO="$url" KOOMPI_DEST="$dest" \
        bash "$INSTALL" 2>&1 < /dev/null )
}
# a repo whose ./setup is a stub: install.sh hands over to it and stops there
stub_repo() {
    local dir="$1" origin="$1/koompi/koompi-desktop.git" seed="$1/seed"
    mkdir -p "$dir/koompi"; git init -q --bare "$origin"
    git clone -q "$origin" "$seed" 2>/dev/null
    printf '#!/usr/bin/env bash\nprintf "stub setup ran: %%s\\n" "$*"\n' > "$seed/setup"
    chmod +x "$seed/setup"
    git -C "$seed" add setup; git -C "$seed" commit -qm setup
    git -C "$seed" push -q origin HEAD:main HEAD:"refs/heads/$RETIRED" HEAD:refs/heads/dev
    printf 'file://%s\n' "$origin"
}

url="$(stub_repo "$T/e")"
dest="$T/e/dest"
out="$(install_into "$url" "$dest")"
[[ "$(branch_of "$dest")" == main ]] || fail "install.sh did not clone main: $out"
grep -q 'tracking main' <<<"$out" || fail "install.sh did not say which line it took: $out"
grep -q 'stub setup ran: install' <<<"$out" || fail "install.sh did not hand over to setup: $out"
pass "install.sh clones main"

dest="$T/e/dev"
out="$(install_into "$url" "$dest" KOOMPI_REF=dev)"
[[ "$(branch_of "$dest")" == dev ]] || fail "KOOMPI_REF=dev was not honoured: $out"
pass "KOOMPI_REF still picks another branch"

git -C "$(seed_of "${url#file://}")" tag v1
git -C "$(seed_of "${url#file://}")" push -q origin v1
out="$(install_into "$url" "$T/e/dest" KOOMPI_REF=v1)"
grep -q 'stub setup ran: install' <<<"$out" || fail "a re-run with KOOMPI_REF set to a tag died: $out"
pass "a re-run with KOOMPI_REF set to a tag still installs"

# --- a re-run repairs a checkout made when installs followed prod-hd ----------
dest="$T/e/old"
git clone -q --depth 1 --branch "$RETIRED" "$url" "$dest" 2>/dev/null
git -C "$(seed_of "${url#file://}")" push -q origin --delete "$RETIRED"
out="$(install_into "$url" "$dest")"
[[ "$(branch_of "$dest")" == main ]] || fail "a re-run left an old $RETIRED checkout off main: $out"
[[ "$(upstream_of "$dest")" == origin/main ]] || fail "the repaired checkout does not track origin/main: $out"
git -C "$dest" config --get-all remote.origin.fetch | grep -q "$RETIRED" \
    && fail "the re-run kept the $RETIRED refspec"
git -C "$dest" fetch -q origin || fail "the repaired checkout cannot fetch"
grep -q 'stub setup ran: install' <<<"$out" || fail "the re-run did not reach setup: $out"
pass "a re-run moves an old $RETIRED checkout to main with a working fetch"


exit 0
