# dotfiles

Portable Arch Linux + Hyprland dotfiles with a split install flow.

This repo is meant to handle the full lifecycle of a fresh machine:

- `bootstrap.sh` is the single entrypoint that chooses `install.sh` or `setup.sh` based on your environment
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

## Install Paths

Choose one of these two routes:

- Route A: use `bootstrap.sh` as the single entrypoint
- Route B: run `install.sh` and `setup.sh` manually

### Route A: One-Command Bootstrap

This is the simpler route.

Inside `arch-chroot` as `root`, it will install `git` if needed, clone the repo if needed, and run `install.sh`.

After reboot, run the same bootstrap command again as your normal user. It will verify that the install phase completed, clone the repo if needed, and then run `setup.sh`.

```bash
curl -fsSL https://raw.githubusercontent.com/bjoernab/dotfiles/main/bootstrap.sh | bash
```

---

### Route B: Manual Install + Setup

Use this route if you want to run each phase yourself.

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

`install.sh` is the phase-1 bootstrap. It is interactive and prompts you for GPU, audio, network, laptop, and Bluetooth choices, then installs packages, enables services, verifies the result, and prints a final summary before reboot.

### 3. Reboot and run `setup.sh` as your normal user

After rebooting into your installed system, log into your user session and run:

```bash
git clone https://github.com/bjoernab/dotfiles.git ~/dotfiles
cd ~/dotfiles
./setup.sh
```

Run this as your normal user, not as `root`, and not inside `arch-chroot`.

`setup.sh` is the phase-2 post-boot setup. It is also interactive and prompts for optional pieces like Dolphin, Firefox, extra apps, config deployment, and shell setup. It then installs the desktop packages, bootstraps `yay` if needed, creates user directories, and deploys the managed configs, wallpapers, and user scripts.

---

## After Installation

### 4. Use `update.sh` later to keep things in sync

When you want to update both packages and dotfiles:

```bash
cd ~/dotfiles
./update.sh
```

Run this as your normal user in the installed system.

By default, `update.sh` is now a one-click live sync for machines that already use these dotfiles. It will fast-forward the repo when possible, load saved update selections when available, fall back to install-state plus current machine detection, update system and AUR packages, and then re-sync the managed files into your home directory.

If you want the old choose-everything flow, run:

```bash
./update.sh --interactive
```

If you want to skip the automatic repo pull and use the current checkout exactly as-is, run:

```bash
./update.sh --no-pull
```

### 5. Use `uninstall.sh` when you want to remove the managed setup

You can run `uninstall.sh` as `root` either:

- inside `arch-chroot`
- or from the installed Arch system itself

Example:

```bash
git clone https://github.com/bjoernab/dotfiles.git
cd dotfiles
sudo ./uninstall.sh
```

If you are using a live environment, you can still mount the install, enter `arch-chroot`, and run:

```bash
git clone https://github.com/bjoernab/dotfiles.git
cd dotfiles
./uninstall.sh
```

Unlike `install.sh`, this is not limited to `arch-chroot`, but it should be run either from the installed system or from inside `arch-chroot`, not directly from the live ISO itself.

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
- if the repo checkout is clean and has an upstream configured, it will try a fast-forward `git pull` before updating

### `uninstall.sh`

- Arch Linux
- `root`
- inside `arch-chroot` or from the installed Arch system

## Repository Layout

```text
configs/     application configs deployed into ~/.config
home/        user-side files and scripts deployed into $HOME
images/      wallpapers and synced image assets
packages/    package group definitions consumed by the scripts
scripts/     shared helper logic for the main scripts
install.sh   chroot bootstrap phase
bootstrap.sh single-entry bootstrap wrapper
setup.sh     post-boot user setup phase
update.sh    package + dotfile update flow
uninstall.sh removal flow for managed packages and files
```

## Notes

- `install.sh` is chroot-only
- `setup.sh` and `update.sh` are post-boot user-session scripts
- `uninstall.sh` can be run as `root` either inside `arch-chroot` or from the installed Arch system
- `uninstall.sh` should not be run directly from the live ISO outside `arch-chroot`
- package lists are now maintained in `packages/*.txt` rather than inline in the scripts
- many configs use `@HOME@` and `@USER@` placeholders and are rendered during deployment

## Re-running and Failure Handling

- the scripts are designed to be safe to re-run
- package installs use `pacman --needed` and `yay --needed`, so already-installed packages are skipped instead of blindly reinstalled
- if `install.sh` fails part way through, it does not perform a full rollback of package or service changes that already succeeded
- in practice, a partial `install.sh` failure usually means some packages or services were applied, the failed step is shown in the final summary, and you can fix the issue and run `install.sh` again
- `setup.sh` and `update.sh` back up existing configs and shell files into timestamped backup directories before replacing them
- `setup.sh` backs up replaced files into `~/.config-backup-<timestamp>`
- `update.sh` backs up replaced files into `~/.dotfiles-update-backup-<timestamp>`
- `update.sh` also stores its last selected live-sync state in `~/.local/state/dotfiles/update-state` unless `XDG_STATE_HOME` overrides that base path
- `uninstall.sh` can also move removed home-side files into a timestamped backup directory instead of deleting them outright
- `uninstall.sh` stores those backups under the target user's home in `.dotfiles-uninstall-backup-<timestamp>`
- the scripts print a final passed/failed summary so you can see exactly what completed and what needs attention
- there is no full rollback system; the normal recovery path is to fix the issue and re-run the script
- there is currently no dry-run mode

## How Choices Work

- `install.sh` uses interactive prompts for hardware and base-system choices such as GPU driver, audio stack, networking, laptop support, and Bluetooth
- `setup.sh` uses interactive prompts for optional post-boot choices such as browser, file manager, extra apps, config deployment, and shell setup
- `update.sh` can run either in its default non-interactive live-sync mode or in a fully interactive mode
- by default, `update.sh` now runs in a non-interactive live-sync mode that uses saved selections when available and falls back to install-state plus current machine detection
- `./update.sh --interactive` restores the fully interactive flow
- all of the scripts print the selected options before package and config changes begin so you can see what is about to happen

## Conditional Deployment

- most app configs are only synced when the matching application is installed
- some configs are intentionally gated by dependencies; for example, parts of the desktop config expect NetworkManager and PipeWire to be present
- Eww is a special case: the scripts will still sync `configs/eww` so the bar is ready after a later `yay -S eww` install, while still warning if required runtime pieces are missing
- if a matching app or dependency is missing, the script either skips that config or warns and continues, depending on whether the config is still useful on disk without the runtime package

## Customization Entry Points

- to change what gets installed, edit `packages/*.txt`
- to change what gets deployed into `~/.config`, edit `configs/`
- to change shell files or user scripts copied into `$HOME`, edit `home/`
- to change wallpapers and synced image assets, edit `images/`

## Uninstall User Detection

- when `uninstall.sh` removes home-side files, it tries to detect the target user automatically from `/home`
- if exactly one normal user is found, that user is used automatically
- if multiple eligible users exist, set `DOTFILES_TARGET_USER=<username>` before running `uninstall.sh`
- if user detection is not possible, package removal can still proceed, but home-side cleanup options are skipped

## Customization

You will likely still want to adjust:

- monitor layout
- keybindings
- wallpapers
- themes and fonts
- any machine-specific paths or app choices
