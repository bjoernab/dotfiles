# dotfiles

Portable Arch Linux + Hyprland dotfiles with a split install flow.

This repo is meant to handle the full lifecycle of a fresh machine:

- `install.sh` bootstraps the base system inside `arch-chroot`
- `setup.sh` installs the post-boot desktop stack as your normal user
- `update.sh` updates packages and re-syncs the managed dotfiles later
- `uninstall.sh` removes the managed packages and can optionally clean up deployed files

The repo is structured so the logic stays modular:

- `packages/` holds package group definitions
- `configs/` holds application configs copied into `~/.config`
- `home/` holds user-side files and scripts copied into `$HOME`
- `images/` holds wallpapers and other synced assets
- `scripts/` holds shared helper logic used by the main scripts

## Components

Current managed components include:

- Hyprland
- Hyprpaper
- Hyprlock
- Eww
- Rofi
- Kitty
- Mako
- Fastfetch
- Zsh
- Optional apps such as Dolphin, Firefox, mpv, feh, mousepad, and VS Code

## Recommended Flow

### 1. Install Arch Linux

From the live ISO:

```bash
archinstall
```

Complete the base install normally, then enter the installed system with `arch-chroot`.

### 2. Run `install.sh` inside `arch-chroot`

Run this as `root`, inside the installed system's `arch-chroot`.

```bash
pacman -S git
git clone https://github.com/bjoernab/dotfiles.git
cd dotfiles
./install.sh
```

`install.sh` is the phase-1 bootstrap. It handles core packages, GPU/audio/network choices, laptop and Bluetooth options, service enablement, and verification before reboot.

### 3. Reboot and run `setup.sh` as your normal user

After rebooting into your installed system, log into your user session and run:

```bash
git clone https://github.com/bjoernab/dotfiles.git ~/dotfiles
cd ~/dotfiles
./setup.sh
```

Run this as your normal user, not as `root`, and not inside `arch-chroot`.

`setup.sh` is the phase-2 post-boot setup. It installs the desktop packages, bootstraps `yay` if needed, creates user directories, and deploys the managed configs, wallpapers, and user scripts.

### 4. Use `update.sh` later to keep things in sync

When you want to update both packages and dotfiles:

```bash
cd ~/dotfiles
git pull
./update.sh
```

Run this as your normal user in the installed system.

`update.sh` updates system and AUR packages, ensures the managed package groups are present, and re-syncs the repo's dotfiles into your home directory.

### 5. Use `uninstall.sh` only from `arch-chroot`

If you want to remove the managed system packages and optionally clean up deployed files, boot into a live environment, mount the install, enter `arch-chroot`, and run:

```bash
git clone https://github.com/bjoernab/dotfiles.git
cd dotfiles
./uninstall.sh
```

Like `install.sh`, this must be run as `root` inside `arch-chroot`.

## Script Requirements

### `install.sh`

- Arch Linux
- `root`
- inside `arch-chroot`

### `setup.sh`

- Arch Linux
- normal user session
- outside `arch-chroot`
- `sudo` available

### `update.sh`

- Arch Linux
- normal user session
- outside `arch-chroot`
- `sudo` available

### `uninstall.sh`

- Arch Linux
- `root`
- inside `arch-chroot`

## Repository Layout

```text
configs/     application configs deployed into ~/.config
home/        user-side files and scripts deployed into $HOME
images/      wallpapers and synced image assets
packages/    package group definitions consumed by the scripts
scripts/     shared helper logic for the main scripts
install.sh   chroot bootstrap phase
setup.sh     post-boot user setup phase
update.sh    package + dotfile update flow
uninstall.sh removal flow for managed packages and files
```

## Notes

- `install.sh` and `uninstall.sh` are chroot-only scripts
- `setup.sh` and `update.sh` are post-boot user-session scripts
- package lists are now maintained in `packages/*.txt` rather than inline in the scripts
- many configs use `@HOME@` and `@USER@` placeholders and are rendered during deployment

## Customization

You will likely still want to adjust:

- monitor layout
- keybindings
- wallpapers
- themes and fonts
- any machine-specific paths or app choices
