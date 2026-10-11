-- Grouped (tabbed) windows. Super+G is the widget overlay, so the group chords
-- live on Super+Alt and Super+Shift+G. Required after keybinds.lua, so hl.bind
-- here is already the wrapper that arms the Super-release interrupt.
hl.bind("SUPER + ALT + G", hl.dsp.group.toggle(), { description = "Window: Group or ungroup" })
hl.bind("SUPER + SHIFT + G", hl.dsp.window.move({ out_of_group = true }), { description = "Window: Pull out of its group" })
for _, d in ipairs({ { "Left", "left" }, { "Right", "right" }, { "Up", "up" }, { "Down", "down" } }) do
    hl.bind("SUPER + ALT + " .. d[1], hl.dsp.window.move({ into_group = d[2] }), { description = "Window: Move into the group " .. d[2] })
end
hl.bind("SUPER + ALT + BracketRight", hl.dsp.group.next(), { description = "Window: Next tab in the group" })
hl.bind("SUPER + ALT + BracketLeft", hl.dsp.group.prev(), { description = "Window: Previous tab in the group" })
