export ZSH="$HOME/.oh-my-zsh"
export WORKSPACE="$HOME/workspace"

ZSH_THEME="avit"
plugins=(git)

source $ZSH/oh-my-zsh.sh

source $WORKSPACE/repos/dotfiles/zshrc.d/path.zsh
source $WORKSPACE/repos/dotfiles/zshrc.d/aliases.zsh
source $WORKSPACE/repos/dotfiles/zshrc.d/env.zsh

eval "$($HOME/.local/bin/mise activate zsh)"
source <(op inject -i $WORKSPACE/repos/dotfiles/zshrc.d/secrets.zsh)

