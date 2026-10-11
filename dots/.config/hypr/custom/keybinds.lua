hl.bind("CTRL+SUPER+ALT+Slash", hl.dsp.exec_cmd("xdg-open ~/.config/hypr/custom/keybinds.lua"), {description = "Shell: Edit user keybinds"} )

-- Bare name on purpose: koompi-session prepends ~/.local/bin, so a hand-built kiri
-- wins over the koompi-kiri package in /usr/bin.
hl.bind("SUPER + SHIFT + ALT + code:201", hl.dsp.exec_cmd("kiri voice --lang km"), { description = "Kiri: Khmer dictation" })
hl.bind("SUPER + SHIFT + code:201", hl.dsp.exec_cmd("kiri voice"), { description = "Kiri: Voice transcription" })
hl.bind("SUPER + SHIFT + K", hl.dsp.exec_cmd("kiri voice --lang km"), { description = "Kiri: Khmer dictation" })
hl.bind("SUPER + Escape", hl.dsp.exec_cmd("kiri cancel"), { description = "Kiri: Cancel dictation" })
-- kiri-gui is the Tauri settings app. koompi-kiri does not build it (see that
-- PKGBUILD); this bind only works where kiri-gui was installed by hand.
hl.bind("SUPER + ALT + K", hl.dsp.exec_cmd("kiri-gui"), { description = "Kiri: Settings" })
