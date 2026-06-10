# Hardcoded And Skipped Items

Generated during the initial adoption on 2026-06-09.

## User And Path Hardcoding

- `home/.zshrc:99` uses `/home/remenod/opt/cross/bin`.
- `home/.zshrc:100` uses `/opt/android-sdk/platform-tools`.
- `home/.zshrc:101` uses `/home/remenod/.local/bin`.
- `home/.config/hypr/conf.d/20-programs.conf` points wallpaper to `/home/remenod/.local/share/backgrounds/...`.
- `home/.config/hypr/conf.d/90-binds.conf` calls Waybar volume scripts through absolute `/home/remenod/...` paths.
- `home/.config/waybar/modules/custom/distro.jsonc:18` calls `/home/remenod/.local/bin/fastfetch-popup`.
- `home/.config/waybar/modules/custom/workspace_notes/workspace_note.jsonc:3`, `:7`, and `:8` call workspace-note scripts through absolute `/home/remenod/...` paths.

Most of these can probably become `$HOME`, `~`, or repo-relative helper paths.

## Host And Hardware Specific Items

- `home/.config/hypr/conf.d/10-monitors.conf` hardcodes monitor outputs, refresh rates, positions, transforms, and EDID descriptors.
- `home/.config/waybar/scripts/msi-ec.sh` uses MSI EC sysfs attributes under `/sys/devices/platform/msi-ec`; this is intentionally MSI-specific. Fan RPM reading still uses `isw -r E15CKAMS`, while mode writes use `msi-ec`. Power profiles still use `powerprofilesctl`.
- `home/.config/waybar/scripts/volume.sh` controls MSI mute LEDs through `/sys/devices/platform/msi-ec/leds/platform::mute` and `platform::micmute`.
- `home/.config/waybar/scripts/camera.sh` toggles the MSI EC webcam controls at `/sys/devices/platform/msi-ec/webcam` and `webcam_block`.
- Avoid restoring the old manually installed DKMS `msi_ec/0.08` module. Its Delta 15 config used `mute_led_address = 0x2d`, while the tracked `msi-ec-dkms-git` package maps `15CKEMS1.108` to `mute_led_address = 0x2c`; the old module made the sound mute LED sysfs node accept writes without lighting the physical LED.
- `home/.config/waybar/scripts/kbd_backlight.sh` uses OpenRGB device index defaults, so it depends on detected device order.
- `home/.config/OpenRGB/OpenRGB.json` is intentionally tracked without logs, but it is hardware/device specific.
- `system/etc/udev/rules.d/99-sayodevice.rules` grants access for USB vendor `8089`, apparently for SayoDevice hardware.
- `system/etc/systemd/system/tty1-btm.service:7` contains `User=remenod`.
- `system/etc/systemd/system/tty1-btm.service:11` binds the service to `/dev/tty1`.

Good next step: split monitors, MSI EC controls, OpenRGB, and the tty1 service into a host-specific layer.
