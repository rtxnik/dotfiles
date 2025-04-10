# Only run on macOS
if [[ "$OSTYPE" == "darwin"* ]]; then
	# needed for brew
	eval "$(/opt/homebrew/bin/brew shellenv)"
    export XDG_RUNTIME_DIR="$HOME"/Library/Caches/TemporaryItems
# Only run on Linux distributions
elif [[ -f /etc/os-release ]]; then
    if grep -E "^(ID|NAME)=" /etc/os-release | grep -Eq "ubuntu|fedora"; then
	    # needed for brew to work
	    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
    fi
fi
export XDG_CONFIG_HOME="$HOME"/.config
