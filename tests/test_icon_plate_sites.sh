#!/usr/bin/env bash
# One plate for every app icon (audit section 4, D5): each place the shell draws an app icon goes through
# AppIconPlate, never straight to IconImage or WAppIcon, and the plate's own rules hold: a theme with no body
# metadata is never masked, an icon that resolves to nothing gets a letter, the corner follows rounding_power.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SHELL_ROOT="$REPO_ROOT/dots/.config/quickshell/koompi"
WIDGETS="$SHELL_ROOT/modules/common/widgets"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

SITES=(
    modules/koompi/launchpad/LaunchpadItem.qml
    modules/koompi/overview/SearchItem.qml
    modules/koompi/dock/DockAppButton.qml
    modules/koompi/overview/OverviewWindow.qml
    modules/koompi/bar/Workspaces.qml
    modules/koompi/bar/ActiveWindow.qml
    modules/waffle/bar/AppButton.qml
    modules/waffle/bar/tasks/TaskAppButton.qml
    modules/waffle/bar/tasks/WindowPreview.qml
    modules/waffle/taskView/TaskViewWindow.qml
    modules/waffle/startMenu/startPage/StartAppButton.qml
    modules/waffle/startMenu/startPage/AppCategoryGrid.qml
    modules/waffle/startMenu/searchPage/SearchEntryIcon.qml
    modules/koompi/sidebarRight/volumeMixer/VolumeMixerEntry.qml
    modules/koompi/regionSelector/TargetRegion.qml
    modules/waffle/polkit/WPolkitContent.qml
)

for part in AppIconPlate AppIconPlateBase AppIconPlateMask AppIconPlates AppIconBodies Squircle; do
    [[ -f "$WIDGETS/$part.qml" ]] || fail "missing modules/common/widgets/$part.qml"
done
[[ -f "$WIDGETS/app-icon-plate.js" ]] || fail "missing modules/common/widgets/app-icon-plate.js"

for site in "${SITES[@]}"; do
    file="$SHELL_ROOT/$site"
    [[ -f "$file" ]] || fail "$site is gone; update the site list"
    grep -qE 'AppIconPlate|plated: true' "$file" || fail "$site draws an app icon without AppIconPlate"
    around='IconImage|tryCustomIcon: false|Quickshell\.iconPath\('
    # a search result's action button (open, copy...) is a verb icon, not an app icon
    [[ $site == */SearchItem.qml ]] && around='"image-missing"'
    if grep -nE "$around" "$file"; then
        fail "$site still draws an app icon around the plate"
    fi
done

# the plate has no shader pass of its own per frame: shadow and mask are drawn once, into a cached texture
if grep -nE 'MultiEffect|RectangularShadow|DropShadow|layer\.enabled' "$WIDGETS/AppIconPlate.qml"; then
    fail "AppIconPlate.qml draws an effect itself; effects belong in the renderers that are cached"
fi
grep -q 'grabToImage' "$WIDGETS/AppIconPlateBase.qml" || fail "the plate's shadow is not cached into a texture"
grep -q 'grabToImage' "$WIDGETS/AppIconPlateMask.qml" || fail "the masked icon is not cached into a texture"

if grep -nE '\.(flatMap|flat|at|replaceAll|findLast|toSorted|toReversed)\(|Object\.(hasOwn|fromEntries)' "$WIDGETS/app-icon-plate.js"; then
    fail "app-icon-plate.js uses a method the Quickshell JS engine lacks"
fi
if command -v bun > /dev/null 2>&1; then RUNNER=bun
elif command -v node > /dev/null 2>&1; then RUNNER=node
else echo "skip: neither bun nor node installed, app-icon-plate.js not run"; exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
sed '/^\.pragma /d' "$WIDGETS/app-icon-plate.js" > "$WORK/plate.mjs"
printf '\nexport { bodyBox, bodyThemes, parseIndex, parseOwn, unresolved, bucket, letter, shadowMargin, radiusRatio, cornerHandle, glyphRatio };\n' >> "$WORK/plate.mjs"

cat > "$WORK/run.mjs" <<'EOF'
import * as P from "./plate.mjs";

let failed = 0;
const check = (name, cond, extra = "") => {
    if (!cond) { console.error(`FAIL: ${name} ${extra}`); failed++; }
};
const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);

const idx = P.parseIndex("WhiteSur-green\nfirefox\norg.kde.dolphin\n\n");
check("the index names its theme", idx.theme === "WhiteSur-green", idx.theme);
check("the index lists the theme's own icons", idx.names["firefox"] === true && idx.names["org.kde.dolphin"] === true && !idx.names["missing"]);
check("an empty index is a theme-less one", P.parseIndex("").theme === "" && same(P.parseIndex("").names, {}));
const own = P.parseOwn("google-chrome\t/usr/share/icons/hicolor/64x64/apps/google-chrome.png\nodd name\t/a b/c.svg\nantigravity\t/c/k.png\tcut\n\nno-tab\n");
check("the own-icon index maps each name to its file", same(own["google-chrome"], { path: "/usr/share/icons/hicolor/64x64/apps/google-chrome.png", cut: false }) && same(own["odd name"], { path: "/a b/c.svg", cut: false }));
check("a logo cut from a light tile is marked", same(own["antigravity"], { path: "/c/k.png", cut: true }));
check("the own-icon index skips blank and malformed lines", Object.keys(own).length === 3 && same(P.parseOwn(""), {}));

check("a theme with body metadata masks its own icons", same(P.bodyBox("WhiteSur-green", true), { lo: 0.0625, hi: 0.9375 }));
check("an icon the theme does not draw keeps the plate unmasked", P.bodyBox("WhiteSur-green", false) === null);
check("a theme with no metadata never masks", P.bodyBox("breeze-plus-dark", true) === null);
check("no theme never masks", P.bodyBox("", true) === null);

check("image-missing is unresolved", P.unresolved("image-missing") && P.unresolved("") && P.unresolved(undefined));
check("a real name is resolved", !P.unresolved("firefox"));
check("an unresolved icon shows the first letter of its name", P.letter("konsole") === "K" && P.letter("  zed") === "Z");
check("a label with no letters shows a question mark", P.letter("") === "?" && P.letter("..") === "?");

const shipped = JSON.parse(process.env.SHIPPED_THEMES);
check("the shipped theme names are read from build-theme.sh", shipped.length >= 2, JSON.stringify(shipped));
for (const name of shipped)
    check(`the theme ${name} that build-theme.sh writes has a body box`, P.bodyThemes().includes(name) && P.bodyBox(name, true) !== null);

check("sizes snap up to the next optical size", P.bucket(35) === 48 && P.bucket(32) === 32 && P.bucket(96) === 96 && P.bucket(200) === 256 && P.bucket(1000) === 256);
check("the corner is 28 % of the side", P.radiusRatio() === 0.28);
check("the icon body is 72 % of the plate", P.glyphRatio() === 0.72);

const mid = (4 + 3 * P.cornerHandle()) / 8;
const wanted = Math.pow(2, -1 / 2.5);
check("the corner curve sits on the exponent-2.5 curve of rounding_power", Math.abs(mid - wanted) / wanted < 0.005, `${mid} vs ${wanted}`);
check("the shadow margin grows with the plate", P.shadowMargin(96) > P.shadowMargin(32));

if (failed) process.exit(1);
console.log("ok");
EOF
BUILD_THEME="$REPO_ROOT/sdata/dist-arch/koompi-icons/build-theme.sh"
[[ -f "$BUILD_THEME" ]] || fail "missing sdata/dist-arch/koompi-icons/build-theme.sh"
SHIPPED_THEMES="$(grep -oE "Name=koompi-icons[a-z-]*" "$BUILD_THEME" | sed 's/^Name=//' | sort -u | jq -R . | jq -sc .)"
export SHIPPED_THEMES
cd "$WORK" && "$RUNNER" run.mjs || fail "app-icon-plate.js rules"
echo "ok   icon plate: ${#SITES[@]} sites go through AppIconPlate, effects are cached, theme metadata and fallback rules hold"
