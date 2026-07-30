-- See https://wiki.hypr.land/Configuring/Basics/Binds/
local programs = require("conf.20-programs")

local mainMod = "SUPER" -- Sets "Windows" key as main modifier

-- Example binds, see https://wiki.hypr.land/Configuring/Basics/Binds/ for more
hl.bind(mainMod .. " + R", hl.dsp.exec_cmd(programs.terminal))
hl.bind(mainMod .. " + K", hl.dsp.exec_cmd("kitty"))
hl.bind("ALT + F4", hl.dsp.window.close())
hl.bind("ALT + F24", hl.dsp.window.close())
hl.bind("ALT + SUPER + F24", hl.dsp.window.close())
hl.bind(mainMod .. " + C", hl.dsp.window.close())
hl.bind(mainMod .. " + M", hl.dsp.exec_cmd("command -v hyprshutdown >/dev/null 2>&1 && hyprshutdown || hyprctl dispatch 'hl.dsp.exit()'"))
hl.bind(mainMod .. " + E", hl.dsp.exec_cmd(programs.fileManager))
hl.bind(mainMod .. " + F", hl.dsp.window.float({ action = "toggle" }))
hl.bind(mainMod .. " + P", hl.dsp.window.pseudo()) -- dwindle
hl.bind(mainMod .. " + J", hl.dsp.layout("togglesplit")) -- dwindle only
hl.bind(mainMod .. " + F11", hl.dsp.window.fullscreen_state({ internal = 1, client = -1 }))
hl.bind(mainMod .. " + SHIFT + F11", hl.dsp.window.fullscreen_state({ internal = 2, client = -1 }))

hl.bind("PRINT", hl.dsp.exec_cmd('HYPRSHOT_DIR="$HOME/Pictures/Screenshots" $HOME/.local/bin/hyprshot-safe -m region --freeze'))
hl.bind(mainMod .. " + PRINT", hl.dsp.exec_cmd('HYPRSHOT_DIR="$HOME/Pictures/Screenshots" $HOME/.local/bin/hyprshot-safe -m output --freeze'))
hl.bind(mainMod .. " + SHIFT + PRINT", hl.dsp.exec_cmd('HYPRSHOT_DIR="$HOME/Pictures/Screenshots" $HOME/.local/bin/hyprshot-safe -m window --freeze'))

hl.bind("ALT + left", hl.dsp.exec_cmd("wtype -m alt -k Home"))
hl.bind("ALT + right", hl.dsp.exec_cmd("wtype -m alt -k End"))

hl.bind(mainMod .. " + SHIFT + W", hl.dsp.exec_cmd("~/.config/waybar/scripts/waybar-adaptive.sh reload"))
hl.bind(mainMod .. " + SHIFT + Q", hl.dsp.exec_cmd("pkill mako; mako"))
-- hl.bind(mainMod .. " + SHIFT + E", hl.dsp.exec_cmd("pkill swaybg; swaybg -i " .. programs.wallpaper .. " -m fill"))

hl.bind("CTRL + SHIFT + Escape", hl.dsp.exec_cmd("alacritty -e btm --battery --network_use_bytes --enable_cache_memory --hide-k-threads --show_table_scroll_position --tree --free_arc"))

-- Move focus with mainMod + arrow keys
hl.bind(mainMod .. " + left",  hl.dsp.focus({ direction = "l" }))
hl.bind(mainMod .. " + right", hl.dsp.focus({ direction = "r" }))
hl.bind(mainMod .. " + up",    hl.dsp.focus({ direction = "u" }))
hl.bind(mainMod .. " + down",  hl.dsp.focus({ direction = "d" }))

hl.bind(mainMod .. " + CTRL + left",  hl.dsp.window.move({ direction = "l" }))
hl.bind(mainMod .. " + CTRL + right", hl.dsp.window.move({ direction = "r" }))
hl.bind(mainMod .. " + CTRL + up",    hl.dsp.window.move({ direction = "u" }))
hl.bind(mainMod .. " + CTRL + down",  hl.dsp.window.move({ direction = "d" }))

hl.bind(mainMod .. " + SHIFT + right", hl.dsp.window.resize({ x = 30,  y = 0,   relative = true }), { repeating = true })
hl.bind(mainMod .. " + SHIFT + left",  hl.dsp.window.resize({ x = -30, y = 0,   relative = true }), { repeating = true })
hl.bind(mainMod .. " + SHIFT + up",    hl.dsp.window.resize({ x = 0,   y = -30, relative = true }), { repeating = true })
hl.bind(mainMod .. " + SHIFT + down",  hl.dsp.window.resize({ x = 0,   y = 30,  relative = true }), { repeating = true })

-- Switch workspaces with mainMod + [0-9]
for i = 1, 10 do
    local key = i % 10 -- 10 maps to key 0
    hl.bind(mainMod .. " + " .. key, hl.dsp.focus({ workspace = i }))
end

hl.bind("SUPER + ALT + right", hl.dsp.focus({ workspace = "+1" }), { repeating = true })
hl.bind("SUPER + ALT + left",  hl.dsp.focus({ workspace = "-1" }), { repeating = true })

hl.bind("SUPER + End",  hl.dsp.focus({ workspace = "+1" }), { repeating = true })
hl.bind("SUPER + Home", hl.dsp.focus({ workspace = "-1" }), { repeating = true })

-- Move active window to a workspace with mainMod + SHIFT + [0-9]
for i = 1, 10 do
    local key = i % 10
    hl.bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }))
end

hl.bind("SUPER + ALT + SHIFT + right", hl.dsp.window.move({ workspace = "+1" }), { repeating = true })
hl.bind("SUPER + ALT + SHIFT + left",  hl.dsp.window.move({ workspace = "-1" }), { repeating = true })

hl.bind("SUPER + SHIFT + End",  hl.dsp.window.move({ workspace = "+1" }), { repeating = true })
hl.bind("SUPER + SHIFT + Home", hl.dsp.window.move({ workspace = "-1" }), { repeating = true })

-- Switch workspaces with mainMod + CTRL + [0-9]
for i = 1, 10 do
    local key = i % 10
    hl.bind(mainMod .. " + CTRL + " .. key, hl.dsp.focus({ workspace = i + 10 }))
end

-- Move active window to a workspace with mainMod + CTRL + SHIFT + [0-9]
for i = 1, 10 do
    local key = i % 10
    hl.bind(mainMod .. " + CTRL + SHIFT + " .. key, hl.dsp.window.move({ workspace = i + 10 }))
end

-- Example special workspace (scratchpad)
hl.bind(mainMod .. " + S",         hl.dsp.workspace.toggle_special("magic"))
hl.bind(mainMod .. " + SHIFT + S", hl.dsp.window.move({ workspace = "special:magic" }))

-- Scroll through existing workspaces with mainMod + scroll
-- hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
-- hl.bind(mainMod .. " + mouse_up",   hl.dsp.focus({ workspace = "e-1" }))

hl.bind("mouse:275", hl.dsp.send_shortcut({ mods = "ALT", key = "Left",  window = "activewindow" }))
hl.bind("mouse:276", hl.dsp.send_shortcut({ mods = "ALT", key = "Right", window = "activewindow" }))

-- Move/resize windows with mainMod + LMB and dragging
hl.bind(mainMod .. " + mouse:272",         hl.dsp.window.drag(),   { mouse = true })
hl.bind(mainMod .. " + SHIFT + mouse:272", hl.dsp.window.resize(), { mouse = true })

-- Laptop multimedia keys for volume and LCD brightness
-- hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"), { locked = true, repeating = true })
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("sh -c 'wpctl set-mute @DEFAULT_AUDIO_SINK@ 0; ~/.config/shared/scripts/volume.sh output raise 5'"), { locked = true, repeating = true })

-- hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("~/.config/shared/scripts/volume.sh output lower 5"), { locked = true, repeating = true })

-- hl.bind("XF86AudioMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"), { locked = true, repeating = true })
hl.bind("XF86AudioMute", hl.dsp.exec_cmd("~/.config/shared/scripts/volume.sh output mute"), { locked = true })

-- hl.bind("XF86AudioMicMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"), { locked = true, repeating = true })
hl.bind("XF86AudioMicMute", hl.dsp.exec_cmd("~/.config/shared/scripts/volume.sh input mute"), { locked = true })

hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd([[sh -c 'brightnessctl -e2 -n2 set 5%+ && level=$(brightnessctl -m | awk -F "," "{print \$4}") && notify-send "Brightness: $level" -h int:value:$level -i contrast -h string:x-canonical-private-synchronous:backlight']]), { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd([[sh -c 'brightnessctl -e2 -n2 set 5%- && level=$(brightnessctl -m | awk -F "," "{print \$4}") && notify-send "Brightness: $level" -h int:value:$level -i contrast -h string:x-canonical-private-synchronous:backlight']]), { locked = true, repeating = true })

-- Requires playerctl
hl.bind("XF86AudioNext",  hl.dsp.exec_cmd("playerctl next"),       { locked = true })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPlay",  hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPrev",  hl.dsp.exec_cmd("playerctl previous"),   { locked = true })

hl.bind("CTRL + SUPER + code:202", hl.dsp.exec_cmd("/home/remenod/.config/hypr/scripts/toggle_touchpad.sh"))
hl.bind("code:179",                hl.dsp.exec_cmd("/home/remenod/.config/hypr/scripts/msi-shift-cycle.sh"))
hl.bind("XF86KbdLightOnOff",       hl.dsp.exec_cmd("~/.config/shared/scripts/kbd_backlight.sh cycle"))
hl.bind("XF86RotateWindows",       hl.dsp.exec_cmd("/home/remenod/.config/hypr/scripts/rotate-display-cycle.sh"))
hl.bind("SHIFT + XF86RotateWindows", hl.dsp.exec_cmd("/home/remenod/.config/hypr/scripts/run-spin-frames-shader.sh"))
hl.bind("CTRL + XF86RotateWindows",  hl.dsp.exec_cmd("/home/remenod/.config/hypr/scripts/run-hold-spin-shader.sh start"))
hl.bind("CTRL + XF86RotateWindows",  hl.dsp.exec_cmd("/home/remenod/.config/hypr/scripts/run-hold-spin-shader.sh stop"), { release = true })
hl.bind("XF86RotateWindows",         hl.dsp.exec_cmd("/home/remenod/.config/hypr/scripts/run-hold-spin-shader.sh stop"), { release = true })

hl.bind("ALT + C", hl.dsp.exec_cmd('kdeconnect-cli -n "Makscold" --send-clipboard'))
