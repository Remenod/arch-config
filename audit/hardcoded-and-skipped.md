# Hardcoded And Skipped Items

Generated during the initial adoption on 2026-06-09.

## User And Path Hardcoding

- `home/.zshrc:99` uses `/home/remenod/opt/cross/bin`.
- `home/.zshrc:100` uses `/opt/android-sdk/platform-tools`.
- `home/.zshrc:101` uses `/home/remenod/.local/bin`.
- `home/.config/hypr/hyprland.conf:79` points wallpaper to `/home/remenod/.local/share/backgrounds/...`.
- `home/.config/hypr/hyprland.conf:432`, `:435`, and `:438` call Waybar scripts through absolute `/home/remenod/...` paths.
- `home/.config/waybar/modules/custom/distro.jsonc:18` calls `/home/remenod/.local/bin/fastfetch-popup`.
- `home/.config/waybar/modules/custom/workspace_notes/workspace_note.jsonc:3`, `:7`, and `:8` call workspace-note scripts through absolute `/home/remenod/...` paths.

Most of these can probably become `$HOME`, `~`, or repo-relative helper paths.

## Host And Hardware Specific Items

- `home/.config/hypr/hyprland.conf:46-50` hardcodes monitor outputs, refresh rates, positions, transforms, and EDID descriptors.
- `home/.config/waybar/scripts/fan.sh:9` calls `isw -r E15CKAMS`, tied to this MSI EC firmware family.
- `home/.config/waybar/scripts/fan-menu.sh:27` and `:31` toggle Cooler Boost through `isw`.
- `system/etc/modprobe.d/isw-ec_sys.conf` enables `ec_sys write_support=1` for `isw`.
- `home/.config/waybar/scripts/kbd_backlight.sh` uses OpenRGB device index defaults, so it depends on detected device order.
- `home/.config/OpenRGB/OpenRGB.json` is intentionally tracked without logs, but it is hardware/device specific.
- `system/etc/udev/rules.d/99-sayodevice.rules` grants access for USB vendor `8089`, apparently for SayoDevice hardware.
- `system/etc/systemd/system/tty1-btm.service:7` contains `User=remenod`.
- `system/etc/systemd/system/tty1-btm.service:11` binds the service to `/dev/tty1`.

Good next step: split monitors, fan controls, OpenRGB, and the tty1 service into a host-specific layer.
