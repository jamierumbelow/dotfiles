#!/usr/bin/env bash
set -euo pipefail

WORKSPACE="$HOME/workspace"

info()  { printf "\033[1;34m==> %s\033[0m\n" "$1"; }
warn()  { printf "\033[1;33m==> %s\033[0m\n" "$1"; }
error() { printf "\033[1;31m==> %s\033[0m\n" "$1"; exit 1; }

command_exists() { command -v "$1" &>/dev/null; }

symlink() {
    local src="$1" dst="$2"
    if [ -L "$dst" ]; then
        rm "$dst"
    elif [ -e "$dst" ]; then
        warn "Backing up existing $dst to ${dst}.bak"
        mv "$dst" "${dst}.bak"
    fi
    mkdir -p "$(dirname "$dst")"
    ln -s "$src" "$dst"
    info "Linked $dst -> $src"
}
