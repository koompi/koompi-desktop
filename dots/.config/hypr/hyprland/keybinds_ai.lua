-- The assistant's Control session. Separate file: keybinds.lua is at its file-length
-- allow-list row and may not grow. Required after keybinds.lua, so hl.bind here is
-- already the wrapper that arms the Super-release interrupt.

-- The way out of the assistant driving its browser or your apps, from anywhere and
-- whatever has focus (D9): ends its turn, closes its browser and ends desktop control. Super+Escape is Kiri's cancel
-- (custom/keybinds.lua), hence the Shift.
hl.bind("SUPER + SHIFT + Escape", hl.dsp.global("quickshell:aiControlStop"),
    { description = "Shell: Stop the assistant and end its control" })
