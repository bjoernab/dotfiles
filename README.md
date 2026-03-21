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

## Recommended Flow

### One-Command Bootstrap

If you want a single entrypoint, use `bootstrap.sh`.

Inside `arch-chroot` as `root`, it will install `git` if needed, clone the repo if needed, and run `install.sh`.

After reboot, run the same bootstrap command as your normal user. It will verify that the install phase completed, clone the repo if needed, and then run `setup.sh`.

```bash
curl -fsSL https://raw.githubusercontent.com/bjoernab/dotfiles/main/bootstrap.sh | bash
```

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

### 4. Use `update.sh` later to keep things in sync

When you want to update both packages and dotfiles:

```bash
cd ~/dotfiles
git pull
./update.sh
```

Run this as your normal user in the installed system.

`update.sh` supports both auto-detect and interactive modes. In auto mode it inspects the current machine and selects sensible defaults based on installed packages, services, and existing shell/config state. It then updates system and AUR packages, ensures the managed package groups are present, and re-syncs the repo's dotfiles into your home directory.

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
- `uninstall.sh` can also move removed home-side files into a timestamped backup directory instead of deleting them outright
- `uninstall.sh` stores those backups under the target user's home in `.dotfiles-uninstall-backup-<timestamp>`
- the scripts print a final passed/failed summary so you can see exactly what completed and what needs attention
- there is no full rollback system; the normal recovery path is to fix the issue and re-run the script
- there is currently no dry-run mode

## How Choices Work

- `install.sh` uses interactive prompts for hardware and base-system choices such as GPU driver, audio stack, networking, laptop support, and Bluetooth
- `setup.sh` uses interactive prompts for optional post-boot choices such as browser, file manager, extra apps, config deployment, and shell setup
- `update.sh` starts by letting you choose between auto-detect mode and a fully interactive mode
- in auto-detect mode, `update.sh` inspects installed packages and enabled services to choose defaults before showing the selected actions
- all of the scripts print the selected options before continuing, so you can confirm what is about to happen

## Conditional Deployment

- `setup.sh` and `update.sh` only sync app configs for applications that are actually installed
- some configs are intentionally gated by dependencies; for example, parts of the desktop config expect NetworkManager and PipeWire to be present
- if a matching app or dependency is missing, the script skips that config and reports why instead of forcing a broken deployment

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
