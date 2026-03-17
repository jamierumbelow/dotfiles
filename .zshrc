export ZSH="$HOME/.oh-my-zsh"
export WORKSPACE="$HOME/workspace"

ZSH_THEME="avit"
plugins=(git)

source $ZSH/oh-my-zsh.sh

source $WORKSPACE/repos/dotfiles/zshrc.d/path.zsh
source $WORKSPACE/repos/dotfiles/zshrc.d/aliases.zsh
source $WORKSPACE/repos/dotfiles/zshrc.d/env.zsh
source $WORKSPACE/repos/dotfiles/zshrc.d/functions.zsh

eval "$($HOME/.local/bin/mise activate zsh)"
source <(op --account "$OP_ACCOUNT" inject -i "$WORKSPACE/repos/dotfiles/zshrc.d/secrets.zsh")

cd $WORKSPACE