-- See https://wiki.hypr.land/Configuring/Basics/Window-Rules/ for more
-- See https://wiki.hypr.land/Configuring/Basics/Workspace-Rules/ for workspace rules

-- Example windowrules that are useful

hl.window_rule({
    -- Ignore maximize requests from all apps. You'll probably like this.
    name = "suppress-maximize-events",
    match = { class = ".*" },

    suppress_event = "maximize",
})

hl.window_rule({
    -- Fix some dragging issues with XWayland
    name = "fix-xwayland-drags",
    match = {
        class = "^$",
        title = "^$",
        xwayland = true,
        float = true,
        fullscreen = false,
        pin = false,
    },

    no_focus = true,
})

-- Hyprland-run windowrule
hl.window_rule({
    name = "move-hyprland-run",

    match = { class = "hyprland-run" },

    move = { 20, "monitor_h-120" },
    float = true,
})

hl.window_rule({ match = { class = "alacritty-popup-menu" },   float = true, center = true, size = { 400, 300 }, workspace = "special" })
hl.window_rule({ match = { class = "alacritty-fastfetch" },    float = true, center = true, size = { 900, 500 }, workspace = "special" })
hl.window_rule({ match = { class = "alacritty-connect-menu" }, float = true, center = true, size = { 950, 600 }, workspace = "special" })
hl.window_rule({ match = { class = "steam" }, float = true })
hl.window_rule({ match = { class = "steam", title = "Steam" }, tile = true })

hl.window_rule({
    -- Export panel of the patched Telegram Desktop: it draws its own shadow
    -- and rounded corners on a translucent window, so Hyprland's border,
    -- shadow and blur end up around the empty margins.
    name = "telegram-export-panel",
    match = { class = "^org\\.telegram\\.desktop$", title = "^Telegram Desktop Export$" },

    border_size = 0,
    rounding = 0,
    no_shadow = true,
    no_blur = true,
})
