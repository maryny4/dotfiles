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

## WireGuard toggle

Install the narrowly scoped polkit rule:

    sudo install -Dm644 system/polkit-1/rules.d/10-wg-toggle.rules \
      /etc/polkit-1/rules.d/10-wg-toggle.rules

It grants local active user `arch` permission to start and stop only
`wg-quick@wg0.service`. WireGuard keys and `/etc/wireguard/wg0.conf` remain
outside the repository.

## Current machine intent

- zram: `/etc/systemd/zram-generator.conf` contains `zram-size = ram / 2`.
- mkinitcpio: NVIDIA modules are early-loaded; hooks include Plymouth and an
  encrypted root. Regenerate with `sudo mkinitcpio -P` after changes.
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
