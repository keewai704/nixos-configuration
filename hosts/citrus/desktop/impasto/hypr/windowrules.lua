hl.window_rule({
    name  = "zen-picture-in-picture",
    match = {
        class = "^(zen-beta)$",
        title = "^(Picture-in-Picture|ピクチャーインピクチャー)$",
    },

    float             = true,
    pin               = true,
    keep_aspect_ratio = true,
    no_initial_focus  = true,
    opaque            = true,
    size              = {960, 540},
    move              = {"monitor_w-984", "monitor_h-564"},
})
