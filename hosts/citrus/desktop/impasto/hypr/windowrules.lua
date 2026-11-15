hl.window_rule({
    name  = "auto-hdr-games-only",
    match = {
        class   = "negative:(steam_app_.*|gamescope)",
        content = "negative:game",
    },

    no_auto_hdr = true,
})
