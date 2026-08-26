#!/usr/bin/env bash
# ============================================================================
#  setup-new-pc.sh — reproduce yahya's ML4W Hyprland desktop on a fresh Arch box
# ============================================================================
#
# Take this file with you (git, USB, scp — whatever) to any other Arch Linux
# machine and run it there. It is split into phases so you can stop, reboot,
# and resume without redoing earlier work:
#
#   ./setup-new-pc.sh                 interactive menu (recommended)
#   ./setup-new-pc.sh --phase NAME    run a single phase directly
#
# Phases, in the order you'd normally run them:
#   install-arch     (bare metal only) partitions a disk and installs base
#                    Arch via the official archinstall tool, if you're
#                    running this from the Arch live ISO with nothing
#                    installed yet. Skipped automatically otherwise.
#   preflight        sanity checks, base tools
#   remove-de        (optional, destructive) uninstall the current DE
#   install-ml4w     official ML4W Hyprland + dotfiles install
#   install-packages every pacman + AUR package installed on the source
#                    machine when this script was generated (see the
#                    NATIVE_PACKAGES / AUR_PACKAGES arrays below)
#   dotfiles         personal git identity (shell/terminal dotfiles are
#                    already handled by install-ml4w — see that phase)
#   custom-config    yahya's keybindings, terminal, statusbar tweaks
#   sddm-theme       login screen matching the hyprlock design
#                    (needs a reboot + one login first — see below)
#
# Nothing here runs unattended: every destructive step asks first, and the
# DE-removal step requires typing the word DELETE, not just "y".
# ============================================================================

set -uo pipefail

STATE_DIR="$HOME/.config/setup-new-pc"
mkdir -p "$STATE_DIR"

# ---- output helpers --------------------------------------------------------
c_reset=$'\e[0m'; c_bold=$'\e[1m'; c_red=$'\e[31m'; c_green=$'\e[32m'; c_yellow=$'\e[33m'; c_blue=$'\e[34m'
info()  { echo "${c_blue}::${c_reset} $*"; }
ok()    { echo "${c_green}OK${c_reset}  $*"; }
warn()  { echo "${c_yellow}!!${c_reset}  $*"; }
err()   { echo "${c_red}xx${c_reset}  $*" >&2; }
heading() { echo; echo "${c_bold}== $* ==${c_reset}"; }

confirm() {
    local reply
    read -r -p "$1 [y/N] " reply
    [[ "$reply" =~ ^[Yy]$ ]]
}

confirm_typed() {
    local reply
    read -r -p "$1 " reply
    [[ "$reply" == "$2" ]]
}

hyprland_is_running() {
    pgrep -x Hyprland >/dev/null 2>&1
}

# ============================================================================
# Phase: install-arch  (bare metal -> installed Arch base, via archinstall)
# ============================================================================
is_live_iso() {
    [ -d /run/archiso ] || grep -qi "archiso" /proc/cmdline 2>/dev/null
}

phase_install_arch() {
    heading "Install Arch Linux (archinstall)"

    if ! is_live_iso; then
        info "Not running from the Arch live ISO — Arch is presumably already"
        info "installed on this machine. Skipping."
        return 0
    fi

    if [ "$EUID" -ne 0 ]; then
        err "Run this phase as root — that's the normal state on the live ISO."
        return 1
    fi

    if ! command -v archinstall >/dev/null 2>&1; then
        info "Installing archinstall..."
        pacman -Sy --needed --noconfirm archinstall
    fi

    warn "About to launch archinstall — Arch Linux's own official guided installer."
    warn "It will ask YOU to pick the target disk and show exactly what it's about"
    warn "to wipe before doing anything irreversible. Nothing here pre-selects a"
    warn "disk or answers that for you — that choice has to be a human's, on a"
    warn "machine you can see."
    warn "When it asks about additional packages, add 'git' so you can clone this"
    warn "repo again after rebooting."
    echo
    if ! confirm "Continue to archinstall now?"; then
        warn "Skipped. Run 'archinstall' yourself whenever you're ready, then come"
        warn "back to this script (from the new install) to continue."
        return 0
    fi

    archinstall
    DID_INSTALL_ARCH=1

    echo
    ok "archinstall finished."
    info "Reboot into the new system, log in as the user you created, get this"
    info "script over there (e.g. 'git clone' this repo), and continue with:"
    info "  ./setup-new-pc.sh"
}

# ============================================================================
# Phase: preflight
# ============================================================================
phase_preflight() {
    heading "Preflight checks"

    if [ "$EUID" -eq 0 ]; then
        err "Run this as your normal user, not root. It calls sudo itself when needed."
        return 1
    fi

    if [ ! -f /etc/os-release ] || ! grep -qi '^ID=arch' /etc/os-release; then
        err "This script only knows how to set things up on Arch Linux."
        return 1
    fi
    ok "Running on Arch Linux."

    if ! sudo -v; then
        err "Could not get sudo access — needed for package installs and SDDM config."
        return 1
    fi
    ok "sudo access confirmed."

    info "Installing base tools (git, curl, jq, base-devel) if missing..."
    sudo pacman -S --needed --noconfirm git curl jq base-devel

    if ! command -v yay >/dev/null 2>&1; then
        info "No AUR helper found — building yay..."
        local tmp; tmp=$(mktemp -d)
        git clone --depth=1 https://aur.archlinux.org/yay-bin.git "$tmp/yay-bin"
        (cd "$tmp/yay-bin" && makepkg -si --noconfirm)
        rm -rf "$tmp"
    fi
    ok "yay is available."

    touch "$STATE_DIR/.preflight-done"
    ok "Preflight complete."
}

# ============================================================================
# Phase: remove-de  (optional, destructive)
# ============================================================================
phase_remove_de() {
    heading "Remove existing desktop environment"

    if ! confirm "This step uninstalls whatever desktop environment is currently on this machine. Do you want to do that now?"; then
        warn "Skipping DE removal. If this machine has no DE yet, that's fine — moving on."
        return 0
    fi

    # Best-effort detection of common DE session/shell packages and non-SDDM
    # display managers. Deliberately narrow: only the packages that *define*
    # the desktop session, never shared infra (NetworkManager, pipewire,
    # polkit, portals, etc.) that other things may still depend on.
    local candidates=(
        gnome-session gnome-shell gdm
        plasma-desktop plasma-workspace sddm-kcm
        xfce4-session
        mate-session-manager
        cinnamon-session
        budgie-desktop
        lxqt-session
        lxsession
        deepin-session-shell
        lightdm lxdm
    )

    local found=()
    for pkg in "${candidates[@]}"; do
        pacman -Qi "$pkg" &>/dev/null && found+=("$pkg")
    done

    if [ "${#found[@]}" -eq 0 ]; then
        info "No known desktop-environment packages detected. Nothing to remove."
        return 0
    fi

    warn "The following packages look like they belong to your current desktop environment:"
    printf '   - %s\n' "${found[@]}"
    warn "Removing them will pull in anything that depends on them too (pacman -Rs)."
    warn "This does NOT touch sddm (Hyprland's display manager) or shared services"
    warn "like NetworkManager, pipewire, bluez, or polkit."
    echo
    if ! confirm_typed "Type DELETE (all caps) to confirm removal, anything else to cancel:" "DELETE"; then
        warn "Cancelled. No packages were removed."
        return 0
    fi

    # -Rs (not -Rns): keeps leftover config files as .pacsave instead of
    # deleting them outright, and pacman still prompts before pulling in any
    # package that something else depends on.
    sudo pacman -Rs "${found[@]}"
    ok "Old desktop environment removed."
}

# ============================================================================
# Phase: install-ml4w  (base Hyprland + ML4W dotfiles)
# ============================================================================
# The profile .dotinst URL below is the confirmed real file behind the
# "com.ml4w.dotfiles.stable" profile (verified against its "id" field on
# GitHub: mylinuxforwork/dotfiles, hyprland-dotfiles-stable.dotinst). Override
# with ML4W_PROFILE_URL=... if you ever want a different profile.
ML4W_PROFILE_URL="${ML4W_PROFILE_URL:-https://raw.githubusercontent.com/mylinuxforwork/dotfiles/master/hyprland-dotfiles-stable.dotinst}"

phase_install_ml4w() {
    heading "Install Hyprland + ML4W dotfiles"

    export PATH="$HOME/.local/bin:$PATH"

    if command -v ml4w-dotfiles-installer >/dev/null 2>&1; then
        info "ml4w-dotfiles-installer already installed — skipping."
    else
        info "Installing ml4w-dotfiles-installer (official method: clone + make install)..."
        local tmp; tmp=$(mktemp -d)
        git clone --depth=1 https://github.com/mylinuxforwork/ml4w-dotfiles-installer "$tmp/ml4w-dotfiles-installer"
        (cd "$tmp/ml4w-dotfiles-installer" && make install)
        rm -rf "$tmp"

        if ! command -v ml4w-dotfiles-installer >/dev/null 2>&1; then
            err "ml4w-dotfiles-installer still not found on PATH after install — check the output above."
            return 1
        fi
        ok "ml4w-dotfiles-installer installed."
    fi

    if [ -d "$HOME/.mydotfiles/com.ml4w.dotfiles.stable" ]; then
        info "The 'com.ml4w.dotfiles.stable' profile is already installed — skipping."
    else
        info "Installing the com.ml4w.dotfiles.stable profile — this pulls in Hyprland,"
        info "hyprlock, quickshell, matugen, and everything else the profile depends on."
        ml4w-dotfiles-installer --install "$ML4W_PROFILE_URL"
    fi

    ok "Base ML4W install complete. Reboot and log into Hyprland before the next phases."
}

# ============================================================================
# Phase: install-packages
# ============================================================================
# Snapshot of everything explicitly installed on the source machine, taken with:
#   pacman -Qqen   (native/repo packages)
#   pacman -Qqem   (AUR / foreign packages)
# Re-run those two commands and paste fresh output here whenever you want this
# script to mirror a newer snapshot. --needed is used everywhere below, so
# re-running this phase (or the whole script) never reinstalls what's already
# there.
NATIVE_PACKAGES=(
    alacritty amd-ucode amdgpu_top android-tools awww base base-devel bash-completion
    blueman breeze brightnessctl btop clinfo cliphist dmidecode docker docker-buildx
    docker-compose efibootmgr expect eza fastfetch figlet firefox fish flatpak fnm fzf
    ggml-cpu ggml-hip git gnome-text-editor gnome-themes-extra grim grub gum gvfs
    gvfs-mtp hashcat hashcat-utils htop hypridle hyprland hyprlock hyprpaper hyprpicker
    hyprshutdown hyprsunset imagemagick inotify-tools jq kitty less libva libva-utils
    linux linux-firmware llama-cpp loupe mako matugen maven monero mosh nano nautilus
    neovim network-manager-applet networkmanager nm-connection-editor noto-fonts-emoji
    npm nvtop nwg-displays nwg-look ollama ollama-rocm openbsd-netcat openssh os-prober
    otf-font-awesome p2pool pacman-contrib pavucontrol pinta pipewire pipewire-alsa
    pipewire-pulse polkit-gnome polkit-kde-agent power-profiles-daemon python-pip
    qt6-virtualkeyboard qt6-wayland qt6ct quickshell rocm-opencl-runtime rocm-smi-lib
    rofi rsync rust scrcpy sddm slurp swaybg swaync tailscale tesseract
    tesseract-data-eng thunar tmux ttf-firacode-nerd ttf-jetbrains-mono-nerd tumbler
    udiskie udisks2 unzip uwsm vim vlc waybar wayvnc wget wireguard-tools wireplumber
    wl-clipboard wofi xclip xdg-desktop-portal-hyprland xmrig xorg-xauth zsh
)

AUR_PACKAGES=(
    android-sdk-platform-tools claude-code grimblast-git hyprmod hyprsysteminfo
    python-pywalfox sunshine-bin visual-studio-code-bin waypaper-git
    whatsapp-linux-desktop yay yay-debug
)

# Package-name patterns worth a heads-up: harmless to install on different
# hardware, but pointless there (AMD GPU / ROCm stack from the source machine).
HARDWARE_SPECIFIC_PATTERN='^(amd-ucode|amdgpu_top|rocm-|ollama-rocm|ggml-hip|libva)'

phase_install_packages() {
    heading "Install every package from the source machine"

    local flagged=()
    for pkg in "${NATIVE_PACKAGES[@]}"; do
        [[ "$pkg" =~ $HARDWARE_SPECIFIC_PATTERN ]] && flagged+=("$pkg")
    done
    if [ "${#flagged[@]}" -gt 0 ]; then
        warn "These look AMD-GPU/ROCm-specific (from the source machine's hardware)."
        warn "Harmless to install on different hardware, just possibly pointless there:"
        printf '   - %s\n' "${flagged[@]}"
        if ! confirm "Install them anyway?"; then
            local filtered=()
            for pkg in "${NATIVE_PACKAGES[@]}"; do
                [[ "$pkg" =~ $HARDWARE_SPECIFIC_PATTERN ]] || filtered+=("$pkg")
            done
            NATIVE_PACKAGES=("${filtered[@]}")
            info "Skipping the flagged packages."
        fi
    fi

    info "Installing ${#NATIVE_PACKAGES[@]} native packages via pacman..."
    sudo pacman -S --needed "${NATIVE_PACKAGES[@]}" || warn "pacman reported at least one problem — check the output above."

    if ! command -v yay >/dev/null 2>&1; then
        err "yay not found — run the preflight phase first."
        return 1
    fi
    info "Installing ${#AUR_PACKAGES[@]} AUR packages via yay (this can take a while — several build from source)..."
    yay -S --needed "${AUR_PACKAGES[@]}" || warn "yay reported at least one problem — check the output above."

    ok "Package install pass complete."
}

# ============================================================================
# Phase: dotfiles  (personal git identity)
# ============================================================================
# Shell, terminal, and font config (fish, kitty, zsh, bash, Xresources,
# gtkrc-2.0, ...) are NOT handled here — they're symlinks into the ML4W
# profile already, so install-ml4w reproduces them byte-for-byte on its own.
# This phase only covers the handful of real, personal files that live
# outside that symlink farm.
#
# Deliberately NOT included, even though it's technically "dotfiles":
# ~/.ssh (private keys), ~/.claude, ~/.npm, ~/.vscode*, ~/.dotnet, ~/.pki —
# these hold credentials/session tokens or machine-specific cache, not
# config worth cloning. Set up SSH keys on the new machine yourself.
phase_dotfiles() {
    heading "Copy personal dotfiles (git identity)"

    cat > "$HOME/.gitconfig" <<'EOF'
[user]
	email = rabiiyahya1@gmail.com
	name = yahya-rabii
EOF
    ok "Wrote ~/.gitconfig"

    mkdir -p "$HOME/.config/git"
    cat > "$HOME/.config/git/ignore" <<'EOF'
**/.claude/settings.local.json
EOF
    ok "Wrote ~/.config/git/ignore"
}

# ============================================================================
# Phase: custom-config  (yahya's personal keybindings/terminal/statusbar)
# ============================================================================
write_custom_lua_single_monitor() {
    cat > "$HOME/.config/hypr/custom.lua" <<'LUA_EOF'
-- Custom user keybindings (not overwritten by ML4W updates)
-- Generated by setup-new-pc.sh — single-monitor layout
local mainMod = "SUPER"

-- fr (AZERTY) keyboard layout setup: the physical number row sends symbol
-- keysyms, not digits, so binds must target those keysyms instead
local is_fr = false
local f = io.open(os.getenv("HOME") .. "/.config/hypr/input.lua", "r")
if f then
    local content = f:read("*all")
    if content:match('kb_layout%s*=%s*"fr"') and not content:match('kb_variant%s*=%s*"us"') then
        is_fr = true
    end
    f:close()
end

local fr_keys = {
    "ampersand", "eacute", "quotedbl", "apostrophe", "parenleft",
    "minus", "egrave", "underscore", "ccedilla", "agrave"
}

-- Navigate workspaces with CTRL + [0-9], move focused window with CTRL + SHIFT + [0-9]
for i = 1, 10 do
    local key = i % 10 -- 10 maps to key 0
    if is_fr then
        key = fr_keys[i]
    end
    hl.bind("CTRL + " .. key,         hl.dsp.focus({ workspace = i }),       { description = "Focus workspace " .. i })
    hl.bind("CTRL + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }), { description = "Move window to workspace " .. i })
end

-- App shortcuts
hl.bind(mainMod .. " + CTRL + F", hl.dsp.exec_cmd("firefox"), { description = "Open Firefox" })
hl.bind(mainMod .. " + A", hl.dsp.exec_cmd("~/.config/hypr/scripts/launcher.sh"), { description = "Open application launcher" })
hl.bind(mainMod .. " + CTRL + SHIFT + S", hl.dsp.exec_cmd("~/.config/hypr/scripts/screenshot.sh"), { description = "Take a screenshot" })
hl.bind("CTRL + Escape", hl.dsp.exec_cmd("~/.config/hypr/scripts/killactive.sh"), { description = "Close the hovered window" })
hl.bind(mainMod .. " + L", hl.dsp.exec_cmd("~/.config/ml4w/scripts/ml4w-power -l"), { description = "Lock Screen" })

-- Cycle focus between windows on the current workspace
hl.bind("SHIFT + Tab", hl.dsp.window.cycle_next({}), { description = "Focus next window in workspace" })
LUA_EOF
}

write_custom_lua_two_monitor() {
    cat > "$HOME/.config/hypr/custom.lua" <<'LUA_EOF'
-- Custom user keybindings (not overwritten by ML4W updates)
-- Generated by setup-new-pc.sh — two-monitor layout
local mainMod = "SUPER"

-- Auto-detect which two outputs are connected. Sorted by name so the choice
-- is stable across reloads; the alphabetically-first output becomes
-- "primary" (holds all 10 numbered workspaces), the second becomes
-- "secondary" (a pure drag-to extension on its own fixed workspace 11).
-- If Hyprland picks the wrong physical screen as primary, just swap which
-- name goes in which variable below.
local detected = hl.get_monitors()
table.sort(detected, function(a, b) return a.name < b.name end)
local primaryMonitor = detected[1] and detected[1].name or "DP-1"
local secondaryMonitor = detected[2] and detected[2].name or "DP-2"

-- Pin workspaces to specific monitors. Without this, Hyprland assigns a
-- workspace to whichever monitor is focused the first time you switch to
-- it.
--
-- All 10 numbered workspaces live on primaryMonitor, so CTRL+[0-9] always
-- operates on it regardless of which monitor currently has focus.
--
-- secondaryMonitor is a pure extension: it gets its own fixed workspace (11)
-- that is never part of the 1-10 rotation, so it just sits there as extra
-- screen space. Dragging a window onto it drops the window into workspace
-- 11, without stealing any of the 1-10 workspaces.
for i = 1, 10 do
    hl.workspace_rule({ workspace = tostring(i), monitor = primaryMonitor, persistent = true, default = (i == 1) })
end
hl.workspace_rule({ workspace = "11", monitor = secondaryMonitor, persistent = true, default = true })

-- fr (AZERTY) keyboard layout setup: the physical number row sends symbol
-- keysyms, not digits, so binds must target those keysyms instead
local is_fr = false
local f = io.open(os.getenv("HOME") .. "/.config/hypr/input.lua", "r")
if f then
    local content = f:read("*all")
    if content:match('kb_layout%s*=%s*"fr"') and not content:match('kb_variant%s*=%s*"us"') then
        is_fr = true
    end
    f:close()
end

local fr_keys = {
    "ampersand", "eacute", "quotedbl", "apostrophe", "parenleft",
    "minus", "egrave", "underscore", "ccedilla", "agrave"
}

-- Navigate workspaces with CTRL + [0-9], move focused window with CTRL + SHIFT + [0-9]
for i = 1, 10 do
    local key = i % 10 -- 10 maps to key 0
    if is_fr then
        key = fr_keys[i]
    end
    hl.bind("CTRL + " .. key,         hl.dsp.focus({ workspace = i }),       { description = "Focus workspace " .. i })
    hl.bind("CTRL + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }), { description = "Move window to workspace " .. i })
end

-- App shortcuts
hl.bind(mainMod .. " + CTRL + F", hl.dsp.exec_cmd("firefox"), { description = "Open Firefox" })
hl.bind(mainMod .. " + A", hl.dsp.exec_cmd("~/.config/hypr/scripts/launcher.sh"), { description = "Open application launcher" })
hl.bind(mainMod .. " + CTRL + SHIFT + S", hl.dsp.exec_cmd("~/.config/hypr/scripts/screenshot.sh"), { description = "Take a screenshot" })
hl.bind("CTRL + Escape", hl.dsp.exec_cmd("~/.config/hypr/scripts/killactive.sh"), { description = "Close the hovered window" })
hl.bind(mainMod .. " + L", hl.dsp.exec_cmd("~/.config/ml4w/scripts/ml4w-power -l"), { description = "Lock Screen" })

-- Send the hovered window to the other monitor. With follow_mouse enabled,
-- Hyprland's "active window" already tracks whatever the cursor is over, so
-- these operate on the hovered window without needing to hit-test manually.
local key1 = is_fr and fr_keys[1] or "1"
local key2 = is_fr and fr_keys[2] or "2"
hl.bind("SHIFT + " .. key2, hl.dsp.window.move({ monitor = secondaryMonitor }), { description = "Move hovered window to secondary monitor" })
hl.bind("SHIFT + " .. key1, hl.dsp.window.move({ monitor = primaryMonitor }),   { description = "Move hovered window to primary monitor" })

-- Cycle focus between windows on the current workspace
hl.bind("SHIFT + Tab", hl.dsp.window.cycle_next({}), { description = "Focus next window in workspace" })

-- Toggle monitor focus between the primary and secondary screens (no window
-- movement, just where the keyboard/mouse focus goes).
hl.bind("CTRL + SHIFT + Tab", function()
    local active = hl.get_active_monitor()
    local target = (active and active.name == primaryMonitor) and secondaryMonitor or primaryMonitor
    hl.dispatch(hl.dsp.focus({ monitor = target }))
end, { description = "Focus the other monitor" })
LUA_EOF
}

write_statusbar_override() {
    mkdir -p "$HOME/.config/ml4w-statusbar"
    cat > "$HOME/.config/ml4w-statusbar/statusbar.json" <<'JSON_EOF'
{
    "bar": {
        "height": 34,
        "reservedHeight": 56,
        "enabled": true,
        "alwaysExpanded": false
    },
    "modules": {
        "left": ["terminal"],
        "center": ["workspaces", "launcher", "clock", "swaync"]
    }
}
JSON_EOF
}

phase_custom_config() {
    heading "Apply personal keybindings, terminal, statusbar"

    if [ ! -d "$HOME/.config/hypr" ]; then
        err "~/.config/hypr not found — run the install-ml4w phase (and reboot into Hyprland) first."
        return 1
    fi

    local monitor_count=""
    while [[ "$monitor_count" != "1" && "$monitor_count" != "2" ]]; do
        read -r -p "How many monitors will this machine use? [1/2] " monitor_count
    done

    if [ "$monitor_count" = "2" ]; then
        write_custom_lua_two_monitor
        ok "Wrote two-monitor custom.lua (primary/secondary auto-detected at runtime)."
    else
        write_custom_lua_single_monitor
        ok "Wrote single-monitor custom.lua."
    fi

    if [ -f "$HOME/.config/ml4w/settings/terminal.sh" ]; then
        echo "kitty" > "$HOME/.config/ml4w/settings/terminal.sh"
        chmod +x "$HOME/.config/ml4w/settings/terminal.sh"
        ok "Default terminal set to kitty."
    else
        warn "~/.config/ml4w/settings/terminal.sh not found — skipping (base install may be incomplete)."
    fi

    write_statusbar_override
    ok "Statusbar override written (workspace indicator always visible)."

    if hyprland_is_running; then
        info "Hyprland is running — reloading config and statusbar..."
        hyprctl reload || warn "hyprctl reload failed — check custom.lua for typos."
        command -v qs >/dev/null 2>&1 && qs ipc call statusbar reload 2>/dev/null
        ok "Reloaded live."
    else
        info "Hyprland isn't running yet — these will take effect on first login."
    fi
}

# ============================================================================
# Phase: sddm-theme  (login screen matching the hyprlock design)
# ============================================================================
phase_sddm_theme() {
    heading "Install matching SDDM login theme"

    local colors_conf="$HOME/.config/hypr/colors.conf"
    local wallpaper_cache="$HOME/.cache/ml4w/hyprland-dotfiles"

    if [ ! -f "$colors_conf" ]; then
        err "No $colors_conf found yet."
        err "This is generated by matugen once you've logged into Hyprland and it has"
        err "applied a wallpaper at least once. Log in, then re-run:"
        err "  $0 --phase sddm-theme"
        return 1
    fi

    if [ ! -f "$wallpaper_cache/blurred_wallpaper.png" ] || [ ! -f "$wallpaper_cache/square_wallpaper.png" ]; then
        err "Wallpaper cache not found in $wallpaper_cache."
        err "Set (or re-set) a wallpaper via Super+Ctrl+W, then re-run this phase."
        return 1
    fi

    get_color() {
        # extract e.g. "$primary = rgba(93cdf6ff)" -> "#93cdf6"
        sed -n "s/^\\\$$1 = rgba(\\([0-9a-fA-F]\\{6\\}\\).*/#\\1/p" "$colors_conf" | head -1
    }

    local C_PRIMARY C_TERTIARY C_SECONDARY C_TEXT C_PRIMARY_TEXT C_OUTLINE C_ERROR C_BACKGROUND
    C_PRIMARY=$(get_color primary)
    C_TERTIARY=$(get_color tertiary)
    C_SECONDARY=$(get_color secondary)
    C_TEXT=$(get_color on_background)
    C_PRIMARY_TEXT=$(get_color on_primary)
    C_OUTLINE=$(get_color outline)
    C_ERROR=$(get_color error)
    C_BACKGROUND=$(get_color background)

    for pair in "primary:$C_PRIMARY" "tertiary:$C_TERTIARY" "secondary:$C_SECONDARY" "text:$C_TEXT" \
                "primaryText:$C_PRIMARY_TEXT" "outline:$C_OUTLINE" "error:$C_ERROR" "background:$C_BACKGROUND"; do
        [ -z "${pair#*:}" ] && { err "Could not read color '${pair%%:*}' from $colors_conf"; return 1; }
    done
    ok "Colors read from your current wallpaper's matugen palette."

    local theme_dir="/usr/share/sddm/themes/ml4w-hyprlock-match"
    local work; work=$(mktemp -d)
    mkdir -p "$work/backgrounds"

    cat > "$work/metadata.desktop" <<'EOF'
[SddmGreeterTheme]
Name=ML4W Hyprlock Match
Description=Login theme matching the custom ML4W hyprlock screen
Author=yahya
Copyright=(c) 2026
License=MIT
Type=sddm-theme
Version=1.0
MainScript=Main.qml
ConfigFile=theme.conf
Theme-Id=ml4w-hyprlock-match
Theme-API=2.0
EOF
    : > "$work/theme.conf"

    cat > "$work/Main.qml" <<'QML_EOF'
import QtQuick 2.15
import Qt5Compat.GraphicalEffects 1.0

Item {
    id: root
    anchors.fill: parent

    readonly property color primaryColor: "__C_PRIMARY__"
    readonly property color tertiaryColor: "__C_TERTIARY__"
    readonly property color secondaryColor: "__C_SECONDARY__"
    readonly property color textColor: "__C_TEXT__"
    readonly property color primaryTextColor: "__C_PRIMARY_TEXT__"
    readonly property color outlineColor: "__C_OUTLINE__"
    readonly property color errorColor: "__C_ERROR__"
    readonly property color backgroundColor: "__C_BACKGROUND__"

    property string timeText: Qt.formatTime(new Date(), "hh:mm")
    property string dateText: Qt.formatDate(new Date(), "dddd, d MMMM")

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: {
            var now = new Date()
            root.timeText = Qt.formatTime(now, "hh:mm")
            root.dateText = Qt.formatDate(now, "dddd, d MMMM")
        }
    }

    property string loginUser: ""
    property int resolvedUserIndex: userModel.lastIndex >= 0 ? userModel.lastIndex : 0

    Repeater {
        model: userModel
        Item {
            Component.onCompleted: {
                if (index === root.resolvedUserIndex) {
                    root.loginUser = name
                }
            }
        }
    }

    Component {
        id: loginCardComponent

        Item {
            anchors.fill: parent
            property alias passwordText: passwordInput.text

            Item {
                id: avatarMask
                width: 130
                height: 130
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: -40

                Image {
                    id: avatarImg
                    anchors.fill: parent
                    source: "backgrounds/avatar.png"
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    visible: false
                }
                Rectangle {
                    id: avatarShape
                    anchors.fill: parent
                    radius: width / 2
                    visible: false
                }
                OpacityMask {
                    anchors.fill: parent
                    source: avatarImg
                    maskSource: avatarShape
                }
                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: "transparent"
                    border.width: 4
                    border.color: root.primaryColor
                }
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: 60
                text: "Welcome back, " + root.loginUser
                color: root.textColor
                font.family: "Fira Sans Semibold"
                font.pixelSize: 18
            }

            Rectangle {
                id: passwordField
                width: 300
                height: 54
                radius: 27
                color: Qt.rgba(1, 1, 1, 0.06)
                border.width: 3
                border.color: passwordInput.activeFocus ? root.primaryColor : root.outlineColor
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: 150

                TextInput {
                    id: passwordInput
                    anchors.fill: parent
                    anchors.leftMargin: 24
                    anchors.rightMargin: 24
                    verticalAlignment: TextInput.AlignVCenter
                    color: root.primaryTextColor
                    font.family: "Fira Sans Semibold"
                    font.pixelSize: 16
                    echoMode: TextInput.Password
                    passwordCharacter: "•"
                    focus: true
                    clip: true

                    Keys.onReturnPressed: root.tryLogin()
                    Keys.onEnterPressed: root.tryLogin()
                    Keys.onEscapePressed: passwordInput.text = ""
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: 24
                    text: "Enter Password"
                    font.italic: true
                    font.family: "Fira Sans"
                    font.pixelSize: 15
                    color: root.outlineColor
                    visible: passwordInput.text.length === 0 && !passwordInput.activeFocus
                }
            }

            Text {
                id: statusText
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: 220
                text: ""
                color: root.errorColor
                font.family: "Fira Sans"
                font.pixelSize: 13
                opacity: 0
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: 260
                text: "Press Enter to log in"
                color: root.outlineColor
                font.family: "Fira Sans"
                font.pixelSize: 13
            }

            Row {
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.rightMargin: 24
                anchors.bottomMargin: 20
                spacing: 18

                Text {
                    text: "Restart"
                    color: root.outlineColor
                    font.family: "Fira Sans"
                    font.pixelSize: 13
                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -8
                        cursorShape: Qt.PointingHandCursor
                        onClicked: sddm.reboot()
                    }
                }
                Text {
                    text: "Shut Down"
                    color: root.outlineColor
                    font.family: "Fira Sans"
                    font.pixelSize: 13
                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -8
                        cursorShape: Qt.PointingHandCursor
                        onClicked: sddm.powerOff()
                    }
                }
            }

            Connections {
                target: sddm
                function onLoginFailed() {
                    statusText.text = "Login failed"
                    statusText.opacity = 1
                    passwordInput.text = ""
                    failFade.start()
                }
            }

            SequentialAnimation {
                id: failFade
                PauseAnimation { duration: 1600 }
                NumberAnimation { target: statusText; property: "opacity"; to: 0; duration: 600 }
            }

            Component.onCompleted: passwordInput.forceActiveFocus()
        }
    }

    property Loader primaryLoader: null

    function tryLogin() {
        var password = primaryLoader && primaryLoader.item ? primaryLoader.item.passwordText : ""
        sddm.login(root.loginUser, password, sessionModel.lastIndex >= 0 ? sessionModel.lastIndex : 0)
    }

    Repeater {
        model: screenModel

        Item {
            x: geometry.x
            y: geometry.y
            width: geometry.width
            height: geometry.height

            Image {
                anchors.fill: parent
                source: "backgrounds/blurred_wallpaper.png"
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
            }

            Rectangle {
                anchors.fill: parent
                color: root.backgroundColor
                opacity: 0.28
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: -300
                text: root.timeText
                color: root.textColor
                font.family: "Fira Sans Semibold"
                font.pixelSize: 130
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: -170
                text: root.dateText
                color: root.outlineColor
                font.family: "Fira Sans Medium"
                font.pixelSize: 22
            }

            Loader {
                id: cardLoader
                anchors.fill: parent
                active: index === 0
                sourceComponent: loginCardComponent
                onLoaded: root.primaryLoader = cardLoader
            }
        }
    }
}
QML_EOF

    sed -i \
        -e "s|__C_PRIMARY__|$C_PRIMARY|g" \
        -e "s|__C_TERTIARY__|$C_TERTIARY|g" \
        -e "s|__C_SECONDARY__|$C_SECONDARY|g" \
        -e "s|__C_TEXT__|$C_TEXT|g" \
        -e "s|__C_PRIMARY_TEXT__|$C_PRIMARY_TEXT|g" \
        -e "s|__C_OUTLINE__|$C_OUTLINE|g" \
        -e "s|__C_ERROR__|$C_ERROR|g" \
        -e "s|__C_BACKGROUND__|$C_BACKGROUND|g" \
        "$work/Main.qml"

    cp "$wallpaper_cache/blurred_wallpaper.png" "$work/backgrounds/blurred_wallpaper.png"
    cp "$wallpaper_cache/square_wallpaper.png" "$work/backgrounds/avatar.png"

    info "Installing theme to $theme_dir (needs sudo)..."
    sudo rm -rf "$theme_dir"
    sudo mkdir -p "$theme_dir"
    sudo cp -r "$work"/* "$theme_dir/"
    sudo chmod -R a+rX "$theme_dir"
    rm -rf "$work"

    info "Activating theme via /etc/sddm.conf.d/ (reversible — delete the file to revert)..."
    sudo mkdir -p /etc/sddm.conf.d
    printf '[Theme]\nCurrent=ml4w-hyprlock-match\n' | sudo tee /etc/sddm.conf.d/custom-theme.conf >/dev/null

    ok "SDDM theme installed and activated. Takes effect on next logout/reboot."
    info "Sanity-check it any time without touching your live session:"
    info "  sddm-greeter-qt6 --test-mode --theme $theme_dir"
}

# ============================================================================
# Menu / entry point
# ============================================================================
run_phase() {
    case "$1" in
        install-arch)       phase_install_arch ;;
        preflight)          phase_preflight ;;
        remove-de)          phase_remove_de ;;
        install-ml4w)       phase_install_ml4w ;;
        install-ml4w-force) rm -rf "$HOME/.mydotfiles"; phase_install_ml4w ;;
        install-packages)   phase_install_packages ;;
        dotfiles)           phase_dotfiles ;;
        custom-config)      phase_custom_config ;;
        sddm-theme)         phase_sddm_theme ;;
        *) err "Unknown phase: $1"; exit 1 ;;
    esac
}

if [ "${1:-}" = "--phase" ] && [ -n "${2:-}" ]; then
    run_phase "$2"
    exit $?
fi

echo "${c_bold}setup-new-pc.sh${c_reset} — reproduce yahya's ML4W Hyprland desktop"
echo
echo "  1) Run everything (install-arch if needed -> preflight -> remove-de -> install-ml4w -> install-packages -> dotfiles -> custom-config)"
echo "  2) install-arch only  (bare metal / live ISO -> installed Arch base)"
echo "  3) preflight only"
echo "  4) remove-de only"
echo "  5) install-ml4w only"
echo "  6) install-packages only  (every pacman + AUR package from the source machine)"
echo "  7) dotfiles only  (personal git identity)"
echo "  8) custom-config only"
echo "  9) sddm-theme only  (run this AFTER first reboot + login + wallpaper set)"
echo "  q) quit"
echo
read -r -p "Choice: " choice

DID_INSTALL_ARCH=0

case "$choice" in
    1)
        phase_install_arch
        if [ "${DID_INSTALL_ARCH:-0}" = "1" ]; then
            echo
            info "Arch is installed — reboot into it and re-run this script to continue"
            info "(preflight -> remove-de -> install-ml4w -> install-packages -> dotfiles -> custom-config)."
            exit 0
        fi
        phase_preflight && phase_remove_de && phase_install_ml4w && phase_install_packages && phase_dotfiles && phase_custom_config
        echo
        ok "Core setup done."
        info "Reboot, log into Hyprland, set a wallpaper (Super+Ctrl+W), then run:"
        info "  $0 --phase sddm-theme"
        ;;
    2) phase_install_arch ;;
    3) phase_preflight ;;
    4) phase_remove_de ;;
    5) phase_install_ml4w ;;
    6) phase_install_packages ;;
    7) phase_dotfiles ;;
    8) phase_custom_config ;;
    9) phase_sddm_theme ;;
    q|Q) exit 0 ;;
    *) err "Unknown choice." ;;
esac
