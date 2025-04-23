# dotfiles

![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)

A carefully crafted development environment for macOS and Linux—shell configurations, editor settings, and productivity scripts designed for efficiency and consistency.

---

## Table of Contents

- [Overview](#overview)
- [Features](#features)  
- [Requirements](#requirements)  
- [Installation](#installation)  
- [Post-Installation](#post-installation)
- [Usage](#usage)  
- [Repository Structure](#repository-structure)  
- [Configuration & Customization](#configuration--customization)  
- [License](#license)  

---

## Overview

This repository contains my personal configuration files for various development tools, terminal environments, and productivity utilities. The goal is to provide a consistent development experience across different machines and operating systems with minimal setup time.

## Features

- **Shells**  
  - **Zsh**: auto-launch `tmux`, auto-load SSH keys, aliases, autosuggestions, syntax highlighting, *pure* prompt.  
  - **Bash**: split between `.bash_profile` and `.bashrc`, environment variables management, Starship integration.  
  - **Readline**: enhanced comfort in `.inputrc`.  

- **Terminal**  
  - **Alacritty**: Gruvbox theme, UbuntuMono Nerd Font, configurable padding and blur.  

- **Editors**  
  - **Vim**: plugins via vim-plug (Gruvbox, ALE, Vim-Go, Pandoc, etc.), flexible auto-format and load.  
  - **Neovim**: based on [LazyVim](https://github.com/LazyVim/LazyVim) with Lua configuration, customized for Go development.  

- **Window Managers & Apps**  
  - **macOS**: scripts to toggle dark/light mode, clipboard management.  
  - **Sway**, **skhd**, **qutebrowser**, **k9s**—ready configs and themes.  

- **Tmux**  
  - Remapped prefix to `Ctrl-a`, plugins via TPM (resurrect, yank, navigator), vi-copy mode.  
  - Improved status bar and window management.

- **Scripts**  
  - A suite of bash utilities for:
    - Backups and system management
    - Blog management and publishing workflows
    - Zettelkasten note-taking system
    - Pomodoro timer and productivity tools
    - DND status management
    - URL encoding and web utilities

- **Cross-Platform**  
  - Supports macOS and major Linux distros (Ubuntu, Fedora).  
  - Conditional configuration based on detected OS.

---

## Requirements

- **Git**  
- **bash** ≥ 4.0 or **zsh**  
- **tmux** ≥ 3.0
- **Homebrew** (macOS or Linuxbrew)  
- **Neovim** ≥ 0.8 or **Vim** ≥ 8.0
- **Terminal utilities**:
  - **fzf**: fuzzy finder
  - **bat**: enhanced cat replacement
  - **fd**: alternative to find
  - **zoxide**: smarter cd command
  - **Starship** (optional): cross-shell prompt

---

## Installation

1. **Clone the repo**  

   ```bash
   git clone https://github.com/xssns/dotfiles.git ~/dotfiles
   cd ~/dotfiles
   ```

2. **Run the setup script**

   ```bash
   ./setup
   ```

   This will create the needed directories in `$XDG_CONFIG_HOME` and symlink your configs.

3. **Restart your shell**

   ```bash
   exec $SHELL --login
   ```

## Post-Installation

After basic installation, you may want to:

1. **Install Tmux Plugin Manager**:

   ```bash
   git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
   ```

2. **Install Vim/Neovim plugins**:

   ```bash
   # For Vim
   vim +PlugInstall +qall
   
   # For Neovim
   nvim --headless "+Lazy sync" +qa
   ```

3. **Install fonts**:

   ```bash
   # On macOS
   brew tap homebrew/cask-fonts
   brew install --cask font-ubuntu-mono-nerd-font
   ```

## Usage

- **Reload shell configs**:

  ```bash
  source ~/.zshrc    # for Zsh
  source ~/.bashrc   # for Bash
  ```

- **Tmux shortcuts**:
  - Reload config: `Ctrl-a r`
  - Enter copy mode: `Ctrl-a [` (vi mode)
  - Create new window: `Ctrl-a c`
  - Split panes: `Ctrl-a |` (vertical), `Ctrl-a -` (horizontal)

- **Vim/Neovim**:
  - Open config: `:e ~/.vimrc` or `:e ~/.config/nvim/init.lua`
  - Update plugins: `:PlugUpdate` (Vim) or `:Lazy sync` (Neovim)

- **Utility scripts**:
  - Most scripts in the `scripts/` directory can be run directly
  - Productivity tools: `pomo`, `focus`, `zet`, etc.

## Repository Structure

```
.
├── alacritty.toml       # Alacritty config
├── .bash_profile        # Bash profile
├── bash/                # Additional Bash configs
│   ├── .bashrc
│   └── …
├── .zshrc               # Zsh main config
├── .zprofile            # Zsh profile for Homebrew & XDG
├── .tmux.conf           # Tmux config
├── .inputrc             # Readline settings
├── vim/                 # Classic Vim setup
│   ├── .vimrc
│   └── setup
├── nvim/                # Neovim (LazyVim) config
│   ├── init.lua
│   └── …
├── macos/               # macOS scripts & utilities
├── fonts/               # Custom fonts (UbuntuMono Nerd)
├── scripts/             # Bash utilities
│   ├── backup
│   ├── blog
│   ├── pomocalc
│   └── …  
└── setup                # Quick-install script
```

## Configuration & Customization

- **Fonts**: drop your TTF/OTF files in `fonts/` and update `alacritty.toml`.

- **Tmux Plugins**: after adding plugins to `.tmux.conf`, run in a session:

  ```bash
  ~/.tmux/plugins/tpm/bin/install_plugins
  ```

- **Vim/Neovim Plugins**: edit plugin list in your config and run:

  ```
  :PlugInstall   " Vim
  :Lazy sync     " Neovim
  ```

- **Custom scripts**: Add your own scripts to the `scripts/` directory and ensure they're executable (`chmod +x`).

- **Environment variables**: Modify `.zshrc` or `.bash_profile` to add your own environment variables.

## License

This project is licensed under the MIT License. See LICENSE for details.
