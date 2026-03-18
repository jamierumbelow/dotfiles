# inject secrets into the shell
inject-secrets() {
    source <(op --account "$OP_ACCOUNT" inject -i "$WORKSPACE/repos/dotfiles/zshrc.d/secrets.zsh")
}

# run a command with secrets injected from 1Password
with-secrets() {
    source <(op --account "$OP_ACCOUNT" run -- "$1")
}

# natural language to zsh via claude
xx() {
    if [[ -z "$1" ]]; then
        echo "Usage: xx \"describe what you want to do\""
        return 1
    fi

    local system="You are a zsh command generator. Output ONLY the raw zsh command(s) to accomplish the request. No explanation, no markdown code fences, no commentary. Do not attempt to run anything. Just output the command text."
    local tmpfile=$(mktemp)

    trap "rm -f $tmpfile; printf '\r\033[K'; trap - INT; return 130" INT

    printf "\033[2m thinking...\033[0m"
    claude -p \
        --no-session-persistence \
        --disallowedTools "Bash Read Write Edit MultiEdit Glob Grep WebSearch WebFetch TodoRead TodoWrite" \
        --append-system-prompt "$system" \
        "$1" > "$tmpfile" 2>/dev/null
    local rc=$?

    trap - INT
    printf "\r\033[K"

    if [[ $rc -ne 0 ]] || [[ ! -s "$tmpfile" ]]; then
        rm -f "$tmpfile"
        [[ $rc -eq 130 ]] && return 130
        printf "\033[1;31mFailed to generate command.\033[0m\n"
        return 1
    fi

    local cmd=$(<"$tmpfile")
    rm -f "$tmpfile"
    cmd=$(echo "$cmd" | sed '/^```/d' | sed '/^[[:space:]]*$/d')

    printf "\n\033[1;36m  %s\033[0m\n\n" "$cmd"
    read -k 1 "confirm?Execute? [y/N] "
    printf "\n"

    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        eval "$cmd"
    fi
}