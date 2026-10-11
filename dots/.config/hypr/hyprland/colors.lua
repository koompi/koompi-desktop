hl.config({
    general = {
        col = {
            active_border   = "rgba(44464f77)",
            inactive_border = "rgba(1a1b2033)",
        },
    },
    group = {
        col = {
            border_active          = "rgba(afc6ffCC)",
            border_inactive        = "rgba(44464f77)",
            border_locked_active   = "rgba(e0bbddCC)",
            border_locked_inactive = "rgba(44464f77)",
        },
        groupbar = {
            col = {
                active          = "rgba(afc6ffFF)",
                inactive        = "rgba(292a2fFF)",
                locked_active   = "rgba(e0bbddFF)",
                locked_inactive = "rgba(292a2fFF)",
            },
            text_color               = "rgba(002f66FF)",
            text_color_inactive      = "rgba(e3e2e9FF)",
            text_color_locked_active = "rgba(412742FF)",
            text_color_locked_inactive = "rgba(e3e2e9FF)",
        },
    },
    misc = {
        background_color = "rgba(121318FF)",
    },
})

hl.window_rule({ -- not sure how to syntax "pin 1"
    match        = { pin = 1 },
    border_color = "rgba(afc6ffAA) rgba(afc6ff77)",
})
