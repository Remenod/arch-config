# Arch Config

Arch Linux dotfiles and system configuration snapshots, split by machine.

`master` is intentionally just the repository index/bootstrap area. Real
configs live on host-specific branches, because display layouts, firmware
tools, device rules, and `/etc` snapshots are not portable enough to mix safely.

## Branches

- `master` - repo map and bootstrap scripts; no machine config.
- `msi-delta-15` - current MSI Delta 15 A5EFK config.
- `dell-precision-5510` - old Dell Precision 5510 config/archive branch.

Avoid merging host branches wholesale. Cherry-pick shared improvements when a
script or config change is actually portable.

## Host Branch Layout

- `home/` - files adopted from `$HOME`; live files in `$HOME` are symlinks back
  into this directory.
- `system/etc/` - selected `/etc` snapshots. These are never restored
  automatically because they need root-level review.
- `packages/` - explicit native/AUR package lists for rebuilding the machine.
- `system/*.txt` - enabled systemd unit snapshots.
- `audit/` - notes about hardcoded paths, hardware-specific settings, skipped
  secrets, and other portability risks.
- `scripts/snapshot-home.sh` - first-time adoption of selected `$HOME` paths
  into `home/`, replacing the live files with symlinks back to the repo.
- `scripts/link-home.sh` - recreates user-level symlinks.
- `scripts/snapshot-system.sh` - refreshes package lists and selected system
  snapshots.

## Bootstrap A New Host Branch

Start from `master`, create the machine branch, then adopt the current machine's
home config and system snapshots:

```sh
git switch master
git switch -c dell-precision-5510
./scripts/snapshot-home.sh
./scripts/snapshot-system.sh
git status --short --ignored
```

`snapshot-home.sh` moves only the allowlisted paths from `$HOME` into `home/`
and replaces them with relative symlinks. `snapshot-system.sh` only snapshots
selected `/etc` files, package lists, and enabled systemd units; it does not
collect anything from `$HOME`.

## Restore A Host

Checkout the machine branch first:

```sh
git switch msi-delta-15
./scripts/link-home.sh
```

The link script moves existing non-symlink files aside with a timestamped
`.backup.*` suffix before creating symlinks.

System files under `system/etc/` are reference snapshots. Review diffs and copy
them manually with `sudo` only when they make sense for the target machine.

## Refresh A Host Branch

```sh
./scripts/snapshot-system.sh
git status
```

Review the diff before committing. Runtime state, histories, caches, app
databases, and secrets should stay out of the repo.

## Never Commit

- SSH private keys, GPG private keys, GitHub CLI auth files, Codex auth state.
- Browser, Electron, VS Code workspace/globalStorage/history, Discord, Claude,
  dconf, Pulse/WirePlumber state, Gradle caches, Go telemetry.
- Shell/editor histories and generated status files.

The `.gitignore` on host branches is intentionally conservative. If something
looks like state rather than config, leave it out.
