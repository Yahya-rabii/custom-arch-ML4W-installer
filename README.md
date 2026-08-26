# arch-pc-setup

A single script that reproduces yahya's ML4W Hyprland desktop on a fresh Arch
Linux machine: removes whatever desktop environment is currently there,
installs Hyprland + the ML4W dotfiles, installs every package from the source
machine, and applies all the personal keybindings/terminal/statusbar/login
screen customizations on top.

It's interactive and split into phases, so you can stop, reboot, and resume
without redoing earlier work.

## What you need in advance

- A fresh (or existing) **Arch Linux** install, with a normal (non-root) user
  that has **sudo** access.
- An **internet connection**.
- The **ML4W dotfiles profile install URL**. Go to
  https://mylinuxforwork.github.io/dotfiles/, pick the profile you want
  (e.g. `com.ml4w.dotfiles.stable`), and copy the URL it gives you for
  `--install`. The `install-ml4w` phase will ask you to paste this — it's not
  baked into the script on purpose (that URL isn't something the script can
  safely guess or cache).
- If this machine has an **existing desktop environment** you want removed,
  know that the `remove-de` phase is destructive. It shows you exactly what
  it detected before touching anything and requires typing `DELETE` to
  confirm — but review that list yourself before typing it.

## How to launch it

```sh
git clone <this-repo-url>
cd arch-pc-setup
chmod +x setup-new-pc.sh
./setup-new-pc.sh
```

Running it with no arguments opens an interactive menu: option 1 runs
everything in order, or you can run any phase on its own. You can also target
a phase directly:

```sh
./setup-new-pc.sh --phase install-ml4w
```

### Phases, in order

| Phase              | What it does |
|---------------------|--------------|
| `preflight`         | Sanity checks (Arch, sudo), installs git/curl/jq/base-devel, builds `yay` if missing |
| `remove-de`         | Optional, destructive: detects and removes the current desktop environment's packages. Skippable. Requires typing `DELETE`. |
| `install-ml4w`      | Runs the official ML4W setup script, then `ml4w-dotfiles-installer --install <url>` (you paste the URL) |
| `install-packages`  | Installs every pacman + AUR package that was explicitly installed on the source machine (embedded in the script as `NATIVE_PACKAGES` / `AUR_PACKAGES`) |
| `dotfiles`          | Writes personal git identity (`~/.gitconfig`, `~/.config/git/ignore`). Shell/terminal dotfiles (fish, kitty, zsh, etc.) come for free from `install-ml4w` since they're part of the ML4W profile. |
| `custom-config`     | Asks how many monitors this machine has, then writes the matching keybindings (`custom.lua`), sets kitty as the default terminal, and applies the always-visible workspace indicator in the status bar |
| `sddm-theme`        | Installs a login screen matching the hyprlock design, using colors read live from this machine's own wallpaper. **Run this one after** the first reboot + login + setting a wallpaper (Super+Ctrl+W) — it needs matugen to have generated a color palette first. |

**Recommended flow:** run option 1 (phases 1–6), reboot, log in, set a
wallpaper, then run `./setup-new-pc.sh --phase sddm-theme`.

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
