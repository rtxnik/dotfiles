# dotfiles
![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)

Personal collection of **dotfiles**—configuration files and scripts to unify and automate my development environment on macOS and Linux.

---

## Table of Contents
- [Features](#features)  
- [Requirements](#requirements)  
- [Installation](#installation)  
- [Usage](#usage)  
- [Repository Structure](#repository-structure)  
- [Configuration & Customization](#configuration--customization)  
- [License](#license)  

---

## Features

- **Shells**  
  - **Zsh**: auto-launch `tmux`, auto-load SSH keys, aliases, autosuggestions, syntax highlighting, *pure* prompt.  
  - **Bash**: split between `.bash_profile` and `.bashrc`, environment variables management, Starship integration.  
  - **Readline**: enhanced comfort in `.inputrc`.  

- **Terminal**  
  - **Alacritty**: Gruvbox theme, UbuntuMono Nerd Font, configurable padding and blur.  

- **Editors**  
  - **Vim**: plugins via vim-plug (Gruvbox, ALE, Vim-Go, Pandoc, etc.), flexible auto-format and load.  
  - **Neovim**: based on [LazyVim](https://github.com/LazyVim/LazyVim) with Lua configuration.  

- **Window Managers & Apps**  
  - **macOS**: scripts to toggle dark/light mode.  
  - **Sway**, **skhd**, **qutebrowser**, **k9s**—ready configs and themes.  

- **Tmux**  
  - Remapped prefix to `Ctrl-a`, plugins via TPM (resurrect, yank, navigator), vi-copy mode.  

- **Scripts**  
  - A suite of bash utilities for backups, blogs, Zettelkasten, Pomodoro timer, DND status, URL encoding, and more.  

- **Cross-Platform**  
  - Supports macOS and major Linux distros (Ubuntu, Fedora).  

---

## Requirements

- **Git**  
- **bash** ≥ 4.0 or **zsh**  
- **tmux**  
- **Homebrew** (macOS or Linuxbrew)  
- **fzf**, **bat**, **fd**, **zoxide**  
- **Neovim** or **Vim**  
- **Starship** (optional)  

---

## Installation

1. **Clone the repo**  
   ```bash
   git clone https://github.com/rtxnik/dotfiles.git ~/dotfiles
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

## Usage

- **Reload shell configs**:
  ```bash
  source ~/.zshrc    # for Zsh
  source ~/.bashrc   # for Bash
  ```

- **Tmux shortcuts**:
  - Reload config: `Ctrl-a r`
  - Enter copy mode: `Ctrl-a [` (vi mode)

- **Vim/Neovim**:
  - Open config: `:e ~/.vimrc` or `:e ~/.config/nvim/init.lua`
  - Update plugins: `:PlugUpdate` (Vim) or `:Lazy sync` (Neovim)

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

## License

This project is licensed under the MIT License. See LICENSE for details.
