# arch-pc-setup

A single script that takes a machine from **nothing** (a blank disk, booted
off the Arch ISO) — or from an existing bare Arch install — to yahya's exact
ML4W Hyprland desktop: partitions and installs Arch, removes whatever desktop
environment is there, installs Hyprland + the ML4W dotfiles, installs every
package from the source machine, and applies all the personal
keybindings/terminal/statusbar/login screen customizations on top.

It's interactive and split into phases, so you can stop, reboot, and resume
without redoing earlier work.

## What you need in advance

- A PC booted from the **Arch Linux install ISO**, with a working internet
  connection (`iwctl` for Wi-Fi if you're not on ethernet) — if you're
  starting from nothing. If Arch is already installed, just a normal
  (non-root) user with **sudo** access is enough.
- Nothing else. `install-ml4w` installs `ml4w-dotfiles-installer` itself
  (official method: clone + `make install`) and installs the
  `com.ml4w.dotfiles.stable` profile from its confirmed `.dotinst` URL,
  both hardcoded in the script — no manual URL-hunting or pasting needed. If
  you ever want a different profile, set `ML4W_PROFILE_URL=<url>` before
  running.
- If this machine has an **existing desktop environment** you want removed,
  know that the `remove-de` phase is destructive. It shows you exactly what
  it detected before touching anything and requires typing `DELETE` to
  confirm — but review that list yourself before typing it.

## The one thing this script will never automate for you

Disk partitioning. The `install-arch` phase hands off to Arch's own official
`archinstall` tool rather than reinventing it, and lets it run in its normal
guided mode — it asks you to pick the target disk and shows exactly what it's
about to wipe before doing anything. Nothing in this script pre-selects a
disk or answers that prompt for you. That choice has to be a human's, on a
machine they can see.

(There's also a community collection of installer/maintenance scripts at
[ArchLinux-Development/ArchLinux-Install-Scripts](https://github.com/ArchLinux-Development/ArchLinux-Install-Scripts)
— e.g. dedicated BTRFS/ZFS installers, a bootloader fixer, font tuning. Not
wired into this script since `archinstall` already covers disk setup
including BTRFS, and unlike `archinstall` these aren't the official
Arch-maintained tool. Worth a manual look if you specifically want BTRFS
snapshots or need to fix a broken bootloader later.)

## How to launch it

**From nothing (blank disk, booted off the Arch ISO):**

```sh
# make sure you're online first (iwctl, or plug in ethernet)
curl -O https://raw.githubusercontent.com/Yahya-rabii/custom-arch-ML4W-installer/master/setup-new-pc.sh
chmod +x setup-new-pc.sh
./setup-new-pc.sh
```

Pick option 1. It runs `install-arch` first (archinstall — pick your disk,
hostname, user, timezone, and make sure to add `git` when it asks about extra
packages), then stops and tells you to reboot. Log into your new plain Arch
system, get the script back onto it (`git clone` the repo, now that `git`
exists), and run `./setup-new-pc.sh` again to continue with the rest.

**From an existing bare Arch install:**

```sh
git clone https://github.com/Yahya-rabii/custom-arch-ML4W-installer.git
cd custom-arch-ML4W-installer
chmod +x setup-new-pc.sh
./setup-new-pc.sh
```

Running it with no arguments opens an interactive menu: option 1 runs
everything in order (skipping `install-arch` automatically since Arch is
already there), or you can run any phase on its own. You can also target a
phase directly:

```sh
./setup-new-pc.sh --phase install-ml4w
```

### Phases, in order

| Phase              | What it does |
|---------------------|--------------|
| `install-arch`      | **Bare metal only.** Detects whether it's running from the live ISO; if so, installs `archinstall` and launches it in guided mode. Skipped automatically if Arch is already installed. |
| `preflight`         | Sanity checks (Arch, sudo), installs git/curl/jq/base-devel, builds `yay` if missing |
| `remove-de`         | Optional, destructive: detects and removes the current desktop environment's packages. Skippable. Requires typing `DELETE`. |
| `install-ml4w`      | Installs `ml4w-dotfiles-installer` (clone + `make install`), then runs it against the `com.ml4w.dotfiles.stable` profile URL — no prompts |
| `install-packages`  | Installs every pacman + AUR package that was explicitly installed on the source machine (embedded in the script as `NATIVE_PACKAGES` / `AUR_PACKAGES`) |
| `dotfiles`          | Writes personal git identity (`~/.gitconfig`, `~/.config/git/ignore`). Shell/terminal dotfiles (fish, kitty, zsh, etc.) come for free from `install-ml4w` since they're part of the ML4W profile. |
| `custom-config`     | Asks how many monitors this machine has, then writes the matching keybindings (`custom.lua`), sets kitty as the default terminal, and applies the always-visible workspace indicator in the status bar |
| `sddm-theme`        | Installs a login screen matching the hyprlock design, using colors read live from this machine's own wallpaper. **Run this one after** the first reboot + login + setting a wallpaper (Super+Ctrl+W) — it needs matugen to have generated a color palette first. |

**Recommended flow:** run option 1. If it had to run `install-arch`, reboot
and re-run the script to pick up where it left off. Once the core phases
finish, reboot, log in, set a wallpaper, then run
`./setup-new-pc.sh --phase sddm-theme`.

## Notes

- Nothing runs unattended. Every destructive step asks first.
- `install-packages` flags AMD GPU/ROCm-specific packages (from the source
  machine's hardware) before installing them, in case the new machine has
  different hardware — you can skip them.
- To refresh the embedded package lists later, run `pacman -Qqen` (native)
  and `pacman -Qqem` (AUR) on the source machine and update the
  `NATIVE_PACKAGES` / `AUR_PACKAGES` arrays in `setup-new-pc.sh`.
- Deliberately **not** copied anywhere in this script: `~/.ssh`, `~/.claude`,
  `~/.npm`, `~/.vscode*`, `~/.dotnet`, `~/.pki` — these hold credentials or
  machine-specific state, not config worth cloning. Set up SSH keys fresh on
  each machine.
