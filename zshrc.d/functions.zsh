# inject secrets into the shell
inject-secrets() {
    source <(op --account "$OP_ACCOUNT" inject -i "$WORKSPACE/repos/dotfiles/zshrc.d/secrets.zsh")
}

# run a command with secrets injected from 1Password
with-secrets() {
    source <(op --account "$OP_ACCOUNT" run -- "$1")
}