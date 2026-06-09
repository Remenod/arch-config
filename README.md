# Arch Config

Dotfiles and local Arch Linux system snapshots for this machine.

## Layout

- `home/` contains files adopted from `$HOME`; live files in `$HOME` are relative symlinks back here.
- `system/etc/` contains snapshots of selected `/etc` files. These are not symlinked automatically because they require root-owned restore decisions.
- `packages/` contains explicit pacman/AUR package lists.
- `system/*.txt` contains enabled systemd unit snapshots.
- `audit/` contains notes about hardcoded user, host, hardware, and skipped sensitive state.

## Restore User Configs

From this repo:

```sh
./scripts/link-home.sh
```

Existing non-symlink files are moved aside with a timestamped `.backup.*` suffix.

## Refresh Snapshots

```sh
./scripts/snapshot-system.sh
```

System files under `system/etc/` are snapshots. Restore them manually with `sudo` after reviewing diffs.
