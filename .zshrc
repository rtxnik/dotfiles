# ~~~~~~~~~~~~~~~ SSH ~~~~~~~~~~~~~~~~~~~~~~~~

# Start ssh-agent if not running
if ! pgrep -qf ssh-agent; then
    eval "$(ssh-agent -s)" >/dev/null
fi

# Automatically add SSH keys from ~/.ssh, excluding public keys (*.pub) and config files
for KEY in ~/.ssh/*; do
    if [[ -f "$KEY" && "$KEY" != *.pub && "$KEY" != *config* ]]; then
        # Check if the key is already added
        FINGERPRINT=$(ssh-keygen -lf "$KEY" | awk '{print $2}')
        if ! ssh-add -l | grep -q "$FINGERPRINT"; then
            ssh-add --apple-use-keychain "$KEY" >/dev/null 2>&1
        fi
    fi
done

# ~~~~~~~~~~~~~~~ Tmux ~~~~~~~~~~~~~~~~~~~~~~~~

# Auto-start or attach to a tmux session
if command -v tmux &> /dev/null; then
  # If inside a tmux session, do nothing
  if [ -z "$TMUX" ]; then
    # If there's an existing tmux session, attach to it; otherwise, start a new session
    tmux attach-session -t default || tmux new-session -s default
  fi
fi

# ~~~~~~~~~~~~~~~ Environment Variables ~~~~~~~~~~~~~~~~~~~~~~~~

# Set to superior editing mode

set -o vi

export VISUAL=nvim
export EDITOR=nvim
export TERM="tmux-256color"

export BROWSER="arc"

# Directories

export REPOS="$HOME/Repos"
export GITUSER="xssns"
export GHREPOS="$REPOS/github.com/$GITUSER"
export DOTFILES="$GHREPOS/dotfiles"
export LAB="$GHREPOS/lab"
export SCRIPTS="$DOTFILES/scripts"
export ICLOUD="$HOME/icloud"
export ZETTELKASTEN="$HOME/Zettelkasten"
export ZSH="$HOME/.zsh/"
export AX="$REPOS/github.com/$GITUSER/axioma"

# Go related. In general all executables and scripts go in .local/bin

export GOBIN="$HOME/.local/bin"
export GOPRIVATE="github.com/$GITUSER/*,gitlab.com/$GITUSER/*"
# export GOPATH="$HOME/.local/share/go"
export GOPATH="$HOME/go/"


# ~~~~~~~~~~~~~~~ Path configuration ~~~~~~~~~~~~~~~~~~~~~~~~

setopt extended_glob null_glob

path=(
    $path                           # Keep existing PATH entries
    $HOME/bin
    $HOME/.local/bin
    $HOME/dotnet
    $SCRIPTS
    $HOME/.krew/bin
    $HOME/.rd/bin                   # Rancher Desktop
)

# Remove duplicate entries and non-existent directories
typeset -U path
path=($^path(N-/))

export PATH


# ~~~~~~~~~~~~~~~ History ~~~~~~~~~~~~~~~~~~~~~~~~

HISTFILE=~/.zsh_history
HISTSIZE=100000
SAVEHIST=100000

setopt HIST_IGNORE_SPACE  # Don't save when prefixed with space
setopt HIST_IGNORE_DUPS   # Don't save duplicate lines
setopt SHARE_HISTORY      # Share history between sessions


# ~~~~~~~~~~~~~~~ Prompt ~~~~~~~~~~~~~~~~~~~~~~~~

PURE_GIT_PULL=0
  fpath+=($HOME/.zsh/pure)


autoload -U promptinit; promptinit
prompt pure


# ~~~~~~~~~~~~~~~ Aliases ~~~~~~~~~~~~~~~~~~~~~~~~

# Utils
alias brewup='brew update; brew upgrade; brew cleanup; brew doctor'

# Network
alias ports='lsof -i -P | grep -i "listen"'

# Editor shortcuts
alias v=nvim
alias sv='sudoedit'

# Directory navigation
alias ..='cd ..'
alias dot='cd $DOTFILES'
alias repos='cd $REPOS'
alias icloud='cd $ICLOUD'
alias scripts='cd $SCRIPTS'
alias docs='cd $DOCUMENTS'
alias down='cd $DOWNLOADS'
alias ztl='cd $ZETTELKASTEN'

# Git shortcuts
alias gs='git status'
alias ga='git add'
alias gc='git commit -m'
alias gp='git push'
alias gpl='git pull'
alias gl='git log --graph --oneline --all --decorate'
alias lg='lazygit'

# System operations
alias e='exit'
alias c='clear'
alias t='tmux'
alias s='startx'

# Configurations management
alias ezr='v $DOTFILES/.zshrc'
alias ezp='v $DOTFILES/.zprofile'
alias ev='cd ~/.config/nvim/ && v init.lua'
alias szr='source $DOTFILES/.zshrc'
alias szp='source $DOTFILES/.zprofile'

# File management
alias cd="z"
alias ll='ls -la'
alias la='ls -lathr'
alias le='eza --color=always --long --no-filesize --icons=always --no-time --no-user --no-permissions
'
alias ffind='find . -name'
alias last='find . -type f -not -path "*/\.*" -exec ls -lrt {} +'

# Development tools
alias bss='browser-sync start --server --files "./*"'
alias sss='sass --watch style.scss:style.min.css --style=compressed'

# Fzf
alias fp="fzf --preview 'bat --style=numbers --color=always --line-range :500 {}'"
alias vf='v $(fp)'

# Pass
alias pc='pass show -c'

alias ax='code ~/Repos/github.com/xssns/axioma/'
alias ztl-cli='cd ~/.local/pipx/venvs/zettelkasten-cli/lib/python3.12/site-packages/zettelkasten_cli'


# ~~~~~~~~~~~~~~~ Zoxide ~~~~~~~~~~~~~~~~~~~~~~~~

eval "$(zoxide init zsh)"


# ~~~~~~~~~~~~~~~ Sourcing ~~~~~~~~~~~~~~~~~~~~~~~~

#source "$HOME/.privaterc"

# ~~~~~~~~~~~~~~~ FZF ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

source <(fzf --zsh)


export FZF_DEFAULT_OPTS=$FZF_DEFAULT_OPTS'
  --color=fg:-1,fg+:#d0d0d0,bg:-1,bg+:#262626
  --color=hl:#87ada3,hl+:#5fd7ff,info:#afaf87,marker:#bb362a
  --color=prompt:#a66685,spinner:#bb362a,pointer:#bb362a,header:#87ada3
  --color=border:#262626,label:#aeaeae,query:#d9d9d9
  --preview-window="border-rounded" --prompt="> " --marker=">" --pointer="◆"
  --separator="─" --scrollbar="│" --info="right"'

# fd instead of fzf

export FZF_DEFAULT_COMMAND="fd --hidden --strip-cwd-prefix --exclude .git"
export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
export FZF_ALT_C_COMMAND="fd --type=d --hidden --strip-cwd-prefix --exclude .git"

# Use fd for listing path candidates.
_fzf_compgen_path() {
  fd --hidden --exclude .git . "$1"
}

# Use fd to generate the list for directory completion
_fzf_compgen_dir() {
  fd --type=d --hidden --exclude .git . "$1"
}

source ~/.config/fzf/fzf-git.sh/

show_file_or_dir_preview="if [ -d {} ]; then eza --tree --color=always {} | head -200; else bat -n --color=always --line-range :500 {}; fi"

export FZF_CTRL_T_OPTS="--preview '$show_file_or_dir_preview'"
export FZF_ALT_C_OPTS="--preview 'eza --tree --color=always {} | head -200'"

# Advanced customization of fzf options via _fzf_comprun function
_fzf_comprun() {
  local command=$1
  shift

  case "$command" in
    cd)           fzf --preview 'eza --tree --color=always {} | head -200' "$@" ;;
    export|unset) fzf --preview "eval 'echo \${}'"         "$@" ;;
    ssh)          fzf --preview 'dig {}'                   "$@" ;;
    *)            fzf --preview "$show_file_or_dir_preview" "$@" ;;
  esac
}

# ~~~~~~~~~~~~~~~ Completion ~~~~~~~~~~~~~~~~~~~~~~~~

fpath+=~/.zfunc

if type brew &>/dev/null; then
    FPATH=$(brew --prefix)/share/zsh-completions:$FPATH
fi

autoload -Uz compinit
compinit -u

zstyle ':completion:*' menu select

source ~/.zsh/zsh-autosuggestions/zsh-autosuggestions.zsh
source ~/.zsh//zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
# Example to install completion:
# talosctl completion zsh > ~/.zfunc/_talosctl


# ~~~~~~~~~~~~~~~ Bat ~~~~~~~~~~~~~~~~~~~~~~~~
export BAT_THEME="gruvbox-dark"


# ~~~~~~~~~~~~~~~ TheFuck ~~~~~~~~~~~~~~~~~~~~~~~~
eval $(thefuck --alias)
eval $(thefuck --alias fk)


fpath+=~/.zfunc; autoload -Uz compinit; compinit
export PATH=$PATH:$(go env GOPATH)/bin
