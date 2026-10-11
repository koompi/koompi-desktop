-- Shape of the group tab strip. Its colours are in colors.lua, which matugen writes.
hl.config({
    group = {
        insert_after_current = true,
        groupbar = {
            enabled = true,
            render_titles = true,
            gradients = true,
            height = 22,
            font_size = 11,
            font_weight_active = "bold",
            font_weight_inactive = "normal",
            indicator_height = 0,
            gradient_rounding = 10,
            gradient_rounding_power = 2.5,
            gaps_in = 3,
            gaps_out = 3,
            text_padding = 8,
            blur = false,
            keep_upper_gap = false,
        },
    },
})
