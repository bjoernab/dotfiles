````markdown
# 🧩 dotfiles

Minimal, portable **Arch Linux + Hyprland** setup with automated bootstrap.

---

## 📸 Preview
*(screenshots coming soon)*

---

## 📦 Overview

This repository contains:

- ⚙️ Bootstrap installer for fresh Arch systems
- 🧩 Hyprland configuration (WIP)
- 📦 Package definitions
- 🔁 Update workflow

### Components (planned / partial)

- Hyprland (Wayland compositor)
- Waybar (status bar)
- Wofi (launcher)
- Kitty (terminal)
- Mako (notifications)
- Shell (bash/zsh)

---

## 🎯 Goal

> ⚡ Fast setup • 🧼 Clean structure • 🔁 Easy portability
````
---

## 🚀 Installation (Recommended Flow)

### 1. Install Arch Linux

From live ISO:

```bash
archinstall
# Complete installation normally.
```

### 2. Chroot into installed system

---

## ⚡ Run the Installer (IMPORTANT)

Before cloning, ensure `git` is installed:

```bash
pacman -Sy git
```

Then run:

```bash
git clone https://github.com/bjoernab/dotfiles.git
cd dotfiles
./install.sh
```

---

## ⚠️ Requirements

* Must be run **inside `arch-chroot`**
* Must be run as **root**
* Requires Arch Linux

The script will **abort** if these conditions are not met.

---

## 📋 What the installer does (Phase 1)

* Installs core packages:

  * git, base-devel, sudo, curl, wget, nano
* Installs networking:

  * NetworkManager
* Installs audio stack:

  * PipeWire, WirePlumber, Pulse compatibility, pavucontrol
* Installs NVIDIA drivers (initial assumption)
* Enables:

  * NetworkManager service
* Verifies installation (SUCCESS / ERROR output)
* Prompts for reboot

---

## ⚠️ Notes

* GPU support is currently **NVIDIA-focused**
* Multi-GPU support (AMD / Intel) planned
* Hyprland config deployment comes in later phases
* Some components are still evolving

---

## 🔄 Update

After setup:

```bash
git pull
./update.sh
```

*(update script WIP)*

---

## 📁 Structure

```text
configs/    → application configs (hypr, waybar, etc.)
packages/   → package lists
scripts/    → modular logic (future)
install.sh  → bootstrap installer (chroot phase)
update.sh   → update script (WIP)
```

---

## 🔧 Customization

You are expected to adjust:

* monitor configuration
* keybindings
* themes / fonts

---

## 🔮 Roadmap

* [ ] Hyprland config deployment
* [ ] Multi-GPU support (AMD / Intel)
* [ ] Profile system (desktop / laptop)
* [ ] Modular installer scripts
* [ ] Optional components (Bluetooth, theming, etc.)
* [ ] Screenshot preview section

---
