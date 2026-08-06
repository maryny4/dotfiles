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

## Freeze forensics

This machine hard-freezes with no trace: the journal stops mid-line because a
frozen kernel never flushes its page cache. Layers that survive that, weakest
to strongest:

    sudo install -Dm644 system/sysctl.d/99-freeze-debug.conf /etc/sysctl.d/99-freeze-debug.conf
    sudo install -Dm644 system/modules-load.d/freeze-debug.conf /etc/modules-load.d/freeze-debug.conf
    sudo install -Dm644 system/systemd/system/freeze-watch.service /etc/systemd/system/freeze-watch.service
    sudo systemctl daemon-reload && sudo systemctl enable --now freeze-watch.service
    sudo modprobe efi_pstore amd64_edac && sudo sysctl --system

- `freeze-watch.service`: userspace sampler, fsynced every 5s. Context only
  (temps, memory, load, top processes) — it cannot explain a hardware hang, but
  it rules memory exhaustion and runaway processes in or out.
- `amd64_edac`: nothing was counting DRAM errors before this. Correctable errors
  accumulating here are the clearest sign of a marginal memory overclock.
- `rasdaemon`: `sudo systemctl enable --now rasdaemon` records MCE/EDAC events to
  a database (`ras-mc-ctl --errors`) instead of only the journal.
- `99-freeze-debug.conf`: converts a soft/hard lockup or 120s hung task into a
  panic, which `efi_pstore` then writes to EFI NVRAM. Read it after the reboot
  with `sudo dmesg | grep -i pstore` and `ls /sys/fs/pstore/`. Trade-off: the box
  reboots itself 20s after a panic instead of sitting frozen.
- netconsole is the highest-fidelity option — it streams the kernel log to
  another host over UDP, so nothing depends on the dying disk:
  `sudo modprobe netconsole netconsole=6666@192.168.0.10/,6666@192.168.0.105/`
  with `nc -ul 6666` listening on the laptop. Only useful while that host is up.

A truly instantaneous lock (CPU stops executing) leaves nothing even for
netconsole. If all layers stay silent, the remaining evidence is EDAC counters
before the event, the BIOS event log, and elimination: run DRAM at JEDEC/stock.

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
