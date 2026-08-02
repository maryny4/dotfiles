# dotfiles

![screenshot](assets/screenshot.png)

Arch + Hyprland desktop configs. Single source of truth for everything deployed
to `$HOME` and `~/.config`, plus package and root-owned system manifests. No
secrets — see `.gitignore`.

## Layout

Mirrors `~` and `~/.config`:

- `.bashrc`, `.bash_profile` → `~`
- `hypr/`, `waybar/`, `swaync/`, `fuzzel/`, `kitty/`, `yazi/`, `nvim/`,
  `gtk-3.0/`, `gtk-4.0/`, `environment.d/`, `git/`, `hypr-rdp/`, `systemd/`,
  `wireplumber/`, `pacman/` → `~/.config/`
- `scripts/` → `~/.local/bin/`
- `applications/` → `~/.local/share/applications/`
- `wallpapers/` → `~/Pictures/wallpapers/`
- `grub-theme/` — GRUB theme, installed separately as root
- `packages/` — explicit official and AUR package manifests
- `system/` — reviewed root-owned settings and installation notes

## Deploy and drift check

The sync is additive: it updates files owned by this repository but never
deletes local secrets, generated state, or host-specific overrides.

    ./scripts/dotfiles-sync --check
    ./scripts/dotfiles-sync

If the checkout is not at `~/dotfiles`, set `DOTFILES_DIR`. The same command is
deployed to `~/.local/bin/dotfiles-sync`.

## Secrets

Never committed (`.gitignore`):

- `hypr-rdp/config.toml` — RDP credentials. The repo ships
  `config.toml.example` with a placeholder:
  `install -Dm600 hypr-rdp/config.toml.example
  ~/.config/hypr-rdp/config.toml`, then edit the installed file.

SSH and WireGuard keys are not part of this repo.

Git identity stays in `~/.config/git/config.local`. GitHub authentication stays
in `gh`; the shared config only delegates credential lookup to `gh auth
git-credential`.

## Session units

`systemd/user/hyprland-session.target` is what makes user units work under
Hyprland: the compositor is started by SDDM, not by systemd, so nothing else
activates `graphical-session.target` and every unit enabled into it stays dead.
`hyprland.lua` starts and stops this target, which binds the real one. The target
declaratively pulls in the complete session: Waybar, Hyprpaper, SwayNC, the
polkit agent, udiskie, the per-window layout helper and clipboard services. No
`systemctl enable` state needs to be reproduced.

These units are stopped with the session; locally defined services also restart
automatically after a failure. Root-owned setup, including the restricted
WireGuard polkit rule, is documented in `system/README.md`.

## nvim plugin versions

`nvim/lazy-lock.json` is committed to pin exact plugin versions. Re-commit it
after `lazy update`.
