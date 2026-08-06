# System configuration

This directory records root-owned configuration that cannot be deployed by the
regular user sync script. Review every command before applying it on another
machine.

## Packages

Install repository packages:

    sudo pacman -S --needed - < packages/official.txt

After bootstrapping `paru`, install AUR packages:

    paru -S --needed - < packages/aur.txt

`redhat-fonts` is listed explicitly because `hyprlock.conf` uses Red Hat
Display, even though it is currently installed as a dependency.

## Root-owned files kept here

Paths under this directory mirror `/etc`. Install them with:

    sudo install -Dm644 system/systemd/zram-generator.conf /etc/systemd/zram-generator.conf
    sudo install -Dm644 system/systemd/journald.conf.d/50-size.conf /etc/systemd/journald.conf.d/50-size.conf
    sudo install -Dm644 system/sysctl.d/99-zram.conf /etc/sysctl.d/99-zram.conf
    sudo install -Dm644 system/docker/daemon.json /etc/docker/daemon.json

- `journald.conf.d/50-size.conf`: the 50M default kept only ~2 days of history.
- `sysctl.d/99-zram.conf`: swappiness/page-cluster tuned for zram, not a disk.
- `docker/daemon.json`: bounded logs plus `live-restore` so package upgrades do
  not kill running containers.

Apply without rebooting: `sudo sysctl --system`,
`sudo systemctl kill -s USR1 systemd-journald`, `sudo systemctl restart docker`.

## hypr-rdp keyboard layout patch

`hypr-rdp-git` is patched locally; see `patches/hypr-rdp/UPSTREAM.md` for the
analysis and the upstream PR. Rebuild after installing the AUR package:

    git clone https://aur.archlinux.org/hypr-rdp-git.git && cd hypr-rdp-git
    # apply patches/hypr-rdp/0001-*.patch to the fetched source, then
    makepkg -si

Then set `keyboard_layout_policy = "compositor"` in
`~/.config/hypr-rdp/config.toml`. Drop the patch once the PR is merged.

## WireGuard toggle

Install the narrowly scoped polkit rule:

    sudo install -Dm644 system/polkit-1/rules.d/10-wg-toggle.rules \
      /etc/polkit-1/rules.d/10-wg-toggle.rules

It grants local active user `arch` permission to start and stop only
`wg-quick@wg0.service`. WireGuard keys and `/etc/wireguard/wg0.conf` remain
outside the repository.

## Current machine intent

- mkinitcpio: NVIDIA modules are early-loaded via `MODULES`; the `kms` hook is
  deliberately absent, otherwise it pulls nouveau and amdgpu into the image and
  more than doubles its size. Regenerate with `sudo mkinitcpio -P` after changes.
- GRUB: encrypted ext4 root, Plymouth, 4K graphics and the bundled `dark`
  theme. The LUKS UUID is intentionally not copied here.
- pacman: color, five parallel downloads, sandboxed `DownloadUser = alpm`, and
  `yazi-git` is ignored because it is managed from AUR.
- SDDM: `sddm-silent-theme` with Qt virtual keyboard integration.
- firewalld: physical LAN is in `public`; SSH and RDP are allowed only from
  `192.168.0.0/24` and `10.10.10.0/24`; `wg0` is in `trusted`.
- Wi-Fi regulatory domain still needs a real country code in
  `/etc/conf.d/wireless-regdom`; do not guess this value.

The expected enabled system units are listed in `enabled-units.txt`. SSH,
firewalld, SDDM and boot configuration should be audited before blindly
reproducing them on different hardware.
