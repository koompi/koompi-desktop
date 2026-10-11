#!/usr/bin/env bash
# J10 (audit F2, decision D6): the Hyprland half of the motion budget. general.lua
# is loaded under plain lua with `hl` stubbed, the way test_touch_output.sh does,
# and every animation leaf and curve it registers is held to the budget:
#   windows and window fades in and out <= 200 ms, layers in <= 200 ms, out <= 150 ms,
#   workspaces 300 ms, everything else <= 200 ms; `global` is set, so a leaf the
#   file does not name inherits 200 ms rather than Hyprland's 800;
#   no curve has a y control above 1 (overshoot);
#   the workspace slide moves at most 292 px between two frames at 60 Hz on 1920 px
#   (the figure the file carried before the retime), measured on the curve it names,
#   both with frames aligned to the start and at the worst phase;
#   workspacesIn/workspacesOut stay inherited, since overriding one desyncs a slide.
# Hyprland's `speed` is in tenths of a second: `hyprctl animations` reports 4.00 for the
# 400 ms workspaces leaf.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
GENERAL="${MOTION_GENERAL:-$REPO_ROOT/dots/.config/hypr/hyprland/general.lua}"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

command -v lua >/dev/null 2>&1 || { echo "lua not installed; skipping"; exit 0; }
[[ -f "$GENERAL" ]] || fail "missing $GENERAL"

out="$(lua - "$GENERAL" <<'LUA' 2>&1
local noop
noop = setmetatable({}, { __call = function() return noop end, __index = function() return noop end })
local leaves, curves = {}, {}
hl = setmetatable({
    curve = function(name, spec) curves[name] = spec.points end,
    animation = function(spec) leaves[spec.leaf] = spec end,
}, { __index = function() return noop end })
dofile(arg[1])

local budget = {
    global = 200,
    windowsIn = 200, windowsOut = 200, windowsMove = 200, fadeIn = 200, fadeOut = 200, border = 200,
    layersIn = 200, layersOut = 150, fadeLayersIn = 200, fadeLayersOut = 150,
    workspaces = 300,
    specialWorkspaceIn = 200, specialWorkspaceOut = 150,
    zoomFactor = 200,
}
local builtin = { default = { { 0, 0.75 }, { 0.15, 1 } }, linear = { { 0, 0 }, { 1, 1 } } }
local problems = {}
local function problem(text) problems[#problems + 1] = text end

local names = {}
for leaf in pairs(leaves) do names[#names + 1] = leaf end
table.sort(names)
for _, leaf in ipairs(names) do
    local spec = leaves[leaf]
    local ms = spec.speed * 100
    if not budget[leaf] then
        problem(leaf .. " has no budget in this test; give it one")
    elseif ms > budget[leaf] then
        problem(string.format("%s runs %g ms, budget %d ms", leaf, ms, budget[leaf]))
    end
    if spec.bezier and not (curves[spec.bezier] or builtin[spec.bezier]) then
        problem(leaf .. " names the curve " .. spec.bezier .. ", which is not defined")
    end
end
if not leaves.global then problem("global is not set: unnamed leaves inherit Hyprland's 800 ms") end
if leaves.workspacesIn or leaves.workspacesOut then
    problem("workspacesIn/workspacesOut are overridden: a slide's two halves desync and open a gap")
end

local curve_names = {}
for name in pairs(curves) do curve_names[#curve_names + 1] = name end
table.sort(curve_names)
for _, name in ipairs(curve_names) do
    local points = curves[name]
    for _, p in ipairs(points) do
        if p[2] > 1 then problem(string.format("curve %s has a y control of %g: it overshoots", name, p[2])) end
    end
end

local function ease(points, t)
    local x1, y1, x2, y2 = points[1][1], points[1][2], points[2][1], points[2][2]
    local lo, hi = 0, 1
    for _ = 1, 60 do
        local s = (lo + hi) / 2
        local x = 3 * (1 - s) ^ 2 * s * x1 + 3 * (1 - s) * s ^ 2 * x2 + s ^ 3
        if x < t then lo = s else hi = s end
    end
    local s = (lo + hi) / 2
    return 3 * (1 - s) ^ 2 * s * y1 + 3 * (1 - s) * s ^ 2 * y2 + s ^ 3
end

local WIDTH, HZ, LIMIT = 1920, 60, 292
local aligned, worst = 0, 0
local ws = leaves.workspaces
if ws then
    local points = curves[ws.bezier] or builtin[ws.bezier]
    if points then
        local ms = ws.speed * 100
        local frames = math.floor(ms * HZ / 1000 + 0.5)
        for i = 0, frames - 1 do
            aligned = math.max(aligned, (ease(points, (i + 1) / frames) - ease(points, i / frames)) * WIDTH)
        end
        local dt = 1000 / HZ / ms
        for k = 0, 400 do
            local t0 = k / 400 * (1 - dt)
            worst = math.max(worst, (ease(points, t0 + dt) - ease(points, t0)) * WIDTH)
        end
        if math.max(aligned, worst) > LIMIT then
            problem(string.format("workspaces slide moves %.0f px in one frame at %d Hz on %d px (limit %d)",
                math.max(aligned, worst), HZ, WIDTH, LIMIT))
        end
    end
else
    problem("workspaces is not set")
end

print(string.format("workspaces: %g ms on %s, peak %.1f px/frame aligned, %.1f at the worst phase (limit %d, %d Hz, %d px)",
    ws and ws.speed * 100 or 0, ws and ws.bezier or "-", aligned, worst, LIMIT, HZ, WIDTH))
if #problems > 0 then
    for _, text in ipairs(problems) do print("FAIL: " .. text) end
    os.exit(1)
end
print(string.format("ok   hyprland leaves: %d inside budget, global %g ms, %d curves, none above y 1",
    #names, leaves.global.speed * 100, #curve_names))
LUA
)"
rc=$?
printf '%s\n' "$out"
(( rc == 0 )) || { printf 'FAIL: general.lua is outside the motion budget\n' >&2; exit 1; }
