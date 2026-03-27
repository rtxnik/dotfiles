#!/usr/bin/env bash
# =============================================================================
# Post-create setup (shared across all profiles)
# =============================================================================

set -euo pipefail

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$1"; }

log "Starting environment setup"

if command -v zsh &>/dev/null; then
    sudo chsh -s "$(command -v zsh)" "$USER" 2>/dev/null || true
fi

if ! command -v chezmoi &>/dev/null; then
    log "Installing chezmoi and applying dotfiles"
    sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply https://github.com/rtxnik/dotfiles.git
else
    log "Updating dotfiles"
    chezmoi update --apply || true
fi

if [[ ! -d "$HOME/.zsh/pure" ]]; then
    log "Installing pure prompt"
    mkdir -p "$HOME/.zsh"
    git clone --depth=1 https://github.com/sindresorhus/pure.git "$HOME/.zsh/pure"
fi

export PATH="$HOME/.local/bin:$PATH"

WORKSPACE_MISE="$PWD/.devcontainer/mise.toml"

if [[ -f "$WORKSPACE_MISE" ]]; then
    log "Merging mise configs (global + workspace)"
    mise trust "$HOME/.config/mise/config.toml" 2>/dev/null || true
    mise trust "$WORKSPACE_MISE"
    
    global_config="$HOME/.config/mise/config.toml"
    merged=$(awk '
    # Pass 1: read profile (workspace) mise.toml — store section->key->line
    NR == FNR {
        if ($0 ~ /^\[/) {
            p_sec = $0
            if (!(p_sec in p_order)) {
                p_order[p_sec] = ++p_count
            }
        } else if ($0 ~ /^[[:space:]]*$/ || $0 ~ /^[[:space:]]*#/) {
            next
        } else if (p_sec != "") {
            key = $0
            sub(/[[:space:]]*=.*/, "", key)
            p_data[p_sec, key] = $0
            if (!((p_sec, key) in p_key_order)) {
                p_keys[p_sec] = p_keys[p_sec] (p_keys[p_sec] ? "\n" : "") key
                p_key_order[p_sec, key] = 1
            }
        }
        next
    }

    # Pass 2: read global config — replace matching keys in correct section
    {
        if ($0 ~ /^\[/) {
            # Flush remaining profile keys for previous section
            if (g_sec != "" && g_sec in p_keys) {
                n = split(p_keys[g_sec], arr, "\n")
                for (i = 1; i <= n; i++) {
                    if (!((g_sec, arr[i]) in emitted)) {
                        print p_data[g_sec, arr[i]]
                    }
                }
                delete p_order[g_sec]
            }
            g_sec = $0
            print
            next
        }

        if (g_sec != "" && $0 !~ /^[[:space:]]*$/ && $0 !~ /^[[:space:]]*#/) {
            key = $0
            sub(/[[:space:]]*=.*/, "", key)
            if ((g_sec, key) in p_data) {
                print p_data[g_sec, key]
                emitted[g_sec, key] = 1
                next
            }
        }
        print
    }

    END {
        # Flush remaining profile keys for last global section
        if (g_sec != "" && g_sec in p_keys) {
            n = split(p_keys[g_sec], arr, "\n")
            for (i = 1; i <= n; i++) {
                if (!((g_sec, arr[i]) in emitted)) {
                    print p_data[g_sec, arr[i]]
                }
            }
            delete p_order[g_sec]
        }
        # Append sections that only exist in the profile
        for (sec in p_order) {
            printf "\n%s\n", sec
            n = split(p_keys[sec], arr, "\n")
            for (i = 1; i <= n; i++) {
                print p_data[sec, arr[i]]
            }
        }
    }
    ' "$WORKSPACE_MISE" "$global_config")

    printf '%s\n' "$merged" > "$global_config.tmp"
    mv "$global_config.tmp" "$global_config"

    mise install --yes || true
fi

# Run profile-specific post-create script if available.
if [[ -n "${WORKSPACE_PROFILE:-}" ]]; then
    profile_script="$HOME/.config/workspaces/profiles/$WORKSPACE_PROFILE/post-create-$WORKSPACE_PROFILE.sh"
    if [[ -f "$profile_script" ]]; then
        log "Running $WORKSPACE_PROFILE profile setup"
        bash "$profile_script"
    fi
fi

log "Setup complete"
