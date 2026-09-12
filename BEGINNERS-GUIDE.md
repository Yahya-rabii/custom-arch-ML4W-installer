# Beginner's guide: building this Hyprland desktop from scratch

This walks you from a blank machine to a working ML4W Hyprland desktop, in order,
assuming you have never installed Arch before. Every command is written out.
Read a step fully before running it — a few of them erase disks.

If you already have Arch installed and just want the desktop, skip to
[Part 3](#part-3--run-the-phases).

**Roughly how long:** 20 min to write the USB, 20-40 min to install the base
system, 30-90 min for the packages (a lot of AUR packages build from source).

---

## What you end up with

Hyprland (a Wayland tiling compositor) with the ML4W dotfiles, waybar as a status
bar, rofi as a launcher, kitty as the terminal, hyprlock for the lock screen, and
an SDDM login screen themed from your wallpaper colors. Plus every package from
the source machine — 132 from the official repos and 12 from the AUR.

## What you need

- The target machine, with a monitor and keyboard attached. You need these even
  if the machine will eventually be headless — the installer is graphical.
- A USB stick, **8 GB or larger**. Everything on it will be destroyed.
- A wired internet connection if possible. Wi-Fi works but is more setup.
- A second working computer to write the USB from. This guide assumes it runs
  Linux; see the notes if it runs Windows or macOS.

---

## Part 1 — Make the bootable USB

### 1.1 Download an ISO

Either works:

- **Arch Linux** — <https://archlinux.org/download/>. The script's `install-arch`
  phase is built for this.
- **EndeavourOS** — <https://endeavouros.com/download/>. Arch underneath with a
  friendlier graphical installer. If you pick this, use `setup-new-pc-eos.sh`
  instead of `setup-new-pc.sh` (see [Part 3](#part-3--run-the-phases)).

Beginners generally have an easier time with EndeavourOS.

### 1.2 A note on Rufus

Rufus is a popular Windows tool for this, and it works — but choose **DD mode**
when it offers you a choice. Arch-based ISOs are "hybrid" images that must be
written as a raw byte stream, and Rufus's ISO mode can produce a stick that
won't boot. On Linux and macOS, Rufus doesn't exist; `dd` below does the same
thing.

### 1.3 Find your USB device name

Plug the stick in, then:

```sh
lsblk -o NAME,SIZE,TYPE,TRAN,MODEL
```

Look for the entry whose size and model match your stick, with `TRAN` showing
`usb` — something like `sdc`. **Write this down and be certain.** The next step
overwrites the named device completely, and pointing it at your internal drive
destroys your operating system. Confirm it is removable:

```sh
cat /sys/block/sdc/removable    # must print 1
```

### 1.4 Write the ISO

Unmount it first (the stick may auto-mount when plugged in):

```sh
udisksctl unmount -b /dev/sdc1
```

Then write. Replace both paths with your own, and note the target is
`/dev/sdc` — the whole disk, **not** `/dev/sdc1`:

```sh
sudo dd if=~/Downloads/your-image.iso of=/dev/sdc bs=4M status=progress oflag=direct conv=fsync
sync
```

This takes a few minutes. When it finishes, `dd` prints how many bytes it copied
— that number must equal the ISO's size.

### 1.5 Plug it into a direct port, not a hub

Write speed should be at least several MB/s. If you see something like
**800 kB/s**, the stick has fallen back to USB 1.1 speed. Check with:

```sh
sudo dmesg | grep -i "not running at top speed"
```

If that matches, move the stick to a **port directly on the machine** — a rear
motherboard port on a desktop — rather than a hub, front-panel header, or
extension cable. A bad link is not only slow; it can drop the device mid-write
and corrupt the result.

### 1.6 Verify the write

Worth doing. A silently corrupt USB wastes far more time later than this check
costs.

```sh
ISO=~/Downloads/your-image.iso
SIZE=$(stat -c %s "$ISO")
sync; echo 3 | sudo tee /proc/sys/vm/drop_caches   # so you read flash, not RAM
sha256sum "$ISO"
sudo head -c "$SIZE" /dev/sdc | sha256sum
```

The two hashes must match.

Arch and EndeavourOS ISOs also ship their own checksum for the root filesystem,
which is the strongest check available:

```sh
sudo mount -o ro /dev/sdc1 /mnt
cd /mnt/arch/x86_64 && sudo sha512sum -c airootfs.sha512
cd / && sudo umount /mnt
```

You want `airootfs.sfs: OK`.

### 1.7 Eject safely

```sh
sync
sudo blockdev --flushbufs /dev/sdc
udisksctl power-off -b /dev/sdc
```

---

## Part 2 — Install the base system

### 2.1 Turn off Secure Boot

**Do this first — it is the most common reason the USB appears not to work.**

These ISOs contain no signed `shimx64.efi` bootloader, so firmware with Secure
Boot enabled refuses them. Symptoms are a "Security Violation" message, or the
machine ignoring the USB and booting your old system as if nothing were plugged
in.

Enter firmware setup (usually **Del** or **F2** at power-on), find Secure Boot,
and disable it. While there, leave the machine in **UEFI** mode rather than
Legacy/CSM.

### 2.2 Boot the USB

Power on and tap the one-time boot menu key: **F12** on most machines, **F7** on
Intel NUC, **F11** on MSI and ASRock, **F8** on Asus, sometimes **Esc**.

If the stick appears twice — once plain, once prefixed `UEFI:` — choose the
**`UEFI:`** entry.

### 2.3 Choose a boot entry

You get a short menu. Pick the **standard/default** entry (on EndeavourOS it
reads "with open source drivers: All GPUs"). That is correct for Intel and AMD
graphics, which covers most machines. Only choose the NVIDIA entry if you have
an RTX-or-newer NVIDIA card.

**If the screen goes black or garbled,** reboot and pick the **fallback
nomodeset** entry. That entry exists exactly for this.

### 2.4 Get online

Wired ethernet needs nothing. For Wi-Fi on the **EndeavourOS** live desktop, use
the network icon in the tray. On the **Arch** ISO, which is text-only:

```sh
iwctl
# then, inside the prompt:
station wlan0 scan
station wlan0 get-networks
station wlan0 connect "Your-Network-Name"
exit
```

Check it works:

```sh
ping -c3 archlinux.org
```

### 2.5 Install

**On EndeavourOS:** the Welcome window has a **Start the Installer** button.
Choose the **Online** method — the Offline method always installs an Xfce
desktop you would then have to remove. When it asks which desktop, pick whatever
you like; this script replaces it anyway, and **"No Desktop"** is the cleanest
starting point.

**On Arch:** run the official guided installer:

```sh
pacman -Sy archinstall
archinstall
```

The script's `install-arch` phase does exactly this, so you can also skip ahead
and let it drive.

Either way:

- When choosing a disk, **read the confirmation screen.** This erases it.
- Create a normal user, and make sure that user **has sudo** (often shown as
  "add to wheel" or "is a superuser"). The script refuses to run as root.
- On Arch, add `git` to the extra-packages list so you can clone this repo after
  rebooting.

Then reboot and remove the USB. You will land at a text login. That is correct —
there is no desktop yet.

---

## Part 3 — Run the phases

### 3.1 Get the script onto the machine

```sh
sudo pacman -S --needed git
git clone https://github.com/Yahya-rabii/custom-arch-ML4W-installer.git
cd custom-arch-ML4W-installer
```

### 3.2 Pick the right script

| Your system | Use |
|---|---|
| Arch Linux | `setup-new-pc.sh` |
| EndeavourOS, CachyOS, Manjaro, any Arch derivative | `setup-new-pc-eos.sh` |

They are identical except for one check. The original requires `ID=arch` in
`/etc/os-release`, but EndeavourOS reports `ID="endeavouros"` with
`ID_LIKE="arch"`, so the original stops immediately with *"This script only
knows how to set things up on Arch Linux."* The `-eos` version also accepts
`ID_LIKE=arch`. If you are on plain Arch, either works.

### 3.3 The phases

Run them in this order. Each is a separate command, so you can stop, reboot, and
resume.

| # | Phase | What it does | Skip it if |
|---|---|---|---|
| 1 | `install-arch` | Launches `archinstall`. Live-ISO only; auto-skips otherwise | Already installed |
| 2 | `preflight` | Installs `git`, `curl`, `jq`, `base-devel`; builds `yay` | Never skip |
| 3 | `remove-de` | **Destructive.** Removes an existing desktop environment | Fresh install with no desktop |
| 4 | `install-ml4w` | Installs the ML4W dotfiles — this *is* the desktop | Never skip |
| 5 | `install-packages` | 132 repo + 12 AUR packages. The slow one | You want a minimal system |
| 6 | `dotfiles` | Writes git identity to `~/.gitconfig` | You want your own git identity |
| 7 | `custom-config` | Keybindings, kitty as default terminal, statusbar | Never skip |
| 8 | `sddm-theme` | Themes the login screen. **Run last, after a reboot** | See 3.6 |

Either use the interactive menu:

```sh
chmod +x setup-new-pc-eos.sh
./setup-new-pc-eos.sh
```

…and choose option 1 to run phases 1-7 in order, or run them one at a time:

```sh
./setup-new-pc-eos.sh --phase preflight
./setup-new-pc-eos.sh --phase install-ml4w
./setup-new-pc-eos.sh --phase install-packages
./setup-new-pc-eos.sh --phase dotfiles
./setup-new-pc-eos.sh --phase custom-config
```

Notes as you go:

- `remove-de` requires typing `DELETE`. **Read the list of packages it prints
  before typing it.**
- `install-packages` flags AMD GPU / ROCm packages that came from the source
  machine's hardware. If your machine isn't AMD, skipping them is fine.
- `custom-config` asks how many monitors you have. Answer `1` or `2`.
- Expect `install-packages` to take a while and print a lot. AUR packages
  compile from source.

### 3.4 Enable the login screen — the step the script does not do

**This catches people out.** The script installs SDDM but never enables it. It
contains no `systemctl` commands at all, because it was written for a machine
that already had a display manager running. On a fresh install nothing has ever
enabled one, so you would reboot back to a text prompt with Hyprland installed
but never starting.

Check:

```sh
systemctl is-enabled sddm
```

If that prints `disabled` or `not-found`:

```sh
sudo systemctl enable sddm
sudo systemctl set-default graphical.target
```

### 3.5 Reboot and log in

```sh
sudo reboot
```

You should now get a graphical SDDM login. Log in, and Hyprland starts.

If you are new to Hyprland: **Super** is the Windows/Command key. **Super+Q**
opens a terminal, **Super+R** the launcher, **Super+C** closes a window. The full
list is in `Hyprland_Keyboard_Shortcuts_files.html` in this repo.

### 3.6 Set a wallpaper, then theme the login screen

Press **Super+Ctrl+W** and choose a wallpaper. **Do this before the last phase.**
That phase reads your wallpaper's colors (via matugen) to build a matching login
theme, and it fails if no palette has been generated yet.

Then:

```sh
cd ~/custom-arch-ML4W-installer
./setup-new-pc-eos.sh --phase sddm-theme
```

Reboot once more and your login screen will match your desktop. **Done.**

---

## Keyboard layout

Two different files, easy to confuse:

| File | Holds |
|---|---|
| `~/.config/hypr/input.lua` | The actual layout — `kb_layout = "us"`, `"fr"`, … |
| `~/.config/hypr/custom.lua` | Your keybindings (written by this script) |

To change layout, edit `input.lua`:

```lua
hl.config({
    input = {
        kb_layout    = "fr",
        kb_variant   = "",
        kb_options   = "grp:alt_shift_toggle",
        ...
    },
})
```

**After changing it, re-run `--phase custom-config`.** The generated `custom.lua`
reads `input.lua` and adapts: on a French AZERTY layout the number row sends
`ampersand`, `eacute`, `quotedbl` … instead of digits, so the workspace binds
have to target those keysyms. If you change the layout without regenerating,
`CTRL+[0-9]` stops switching workspaces.

`input.lua` only affects the Hyprland session. For the login screen and text
console, set it system-wide as well:

```sh
sudo localectl set-x11-keymap fr
sudo localectl set-keymap fr
```

Note that `input.lua` is part of the ML4W profile and an ML4W update can
overwrite it. `custom.lua` is specifically the file ML4W will not touch, which
is why your keybindings live there.

---

## Troubleshooting

**The USB doesn't boot at all.** In order: Secure Boot still enabled; Legacy/CSM
mode fighting the UEFI entry; try another port; re-verify the write ([1.6](#16-verify-the-write)).

**Black screen after choosing a boot entry.** Reboot, choose **fallback
nomodeset**.

**"This script only knows how to set things up on Arch Linux."** You are on an
Arch derivative running the wrong script. Use `setup-new-pc-eos.sh`.

**"Run this as your normal user, not root."** Don't use `sudo` on the script —
it calls `sudo` itself where needed.

**Rebooted into a text prompt, no login screen.** SDDM isn't enabled. See
[3.4](#34-enable-the-login-screen--the-step-the-script-does-not-do).

**`sddm-theme` fails or produces no colors.** You skipped the wallpaper. Log in,
press **Super+Ctrl+W**, set one, then re-run that phase.

**AUR package fails to build.** Re-run the phase; it skips what is already
installed. Persistent failures are usually a broken AUR package rather than
anything here — check its AUR comments page.

**Number keys don't switch workspaces.** Layout changed without regenerating
keybindings. Re-run `--phase custom-config`.

---

## Using this on a server

If the machine is a headless server, **only two phases are appropriate**:

```sh
./setup-new-pc-eos.sh --phase preflight
./setup-new-pc-eos.sh --phase dotfiles
```

Do not use the menu's option 1 there — it chains the desktop phases together and
you get Hyprland, SDDM, waybar, firefox and the rest on a machine with no screen.

Nothing in this script sets up anything server-shaped: no SSH hardening, no
firewall, no static addressing. A minimal baseline, run in this order:

```sh
sudo pacman -S --needed openssh ufw
sudo systemctl enable --now sshd
sudo ufw default deny incoming
sudo ufw allow ssh        # MUST come before enabling, or you lock yourself out
sudo ufw enable
```

Then copy your public key over with `ssh-copy-id`, confirm key login works, and
only then set `PasswordAuthentication no` in `/etc/ssh/sshd_config`. Validate
with `sudo sshd -t` before restarting, and keep your existing session open until
a second one connects.

Avoid unattended automatic updates on Arch. It is a rolling release that
occasionally needs manual intervention, and an unsupervised `pacman -Syu` on a
headless box is a good way to find it unbootable later.
