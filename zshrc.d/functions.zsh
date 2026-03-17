# with-secrets
with-secrets() {
    source <(op --account "$OP_ACCOUNT" run -- "$1")
}