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

# sync every repo in $WORKSPACE/repos with its origin default branch
pull-all() {
    emulate -L zsh
    setopt null_glob

    local repos_dir="${WORKSPACE}/repos"
    local repo repo_name current_branch target_branch remote_head candidate stash_ref stash_name
    local pull_output apply_output
    local git_repo_count=0
    local -a synced=()
    local -a conflicted=()
    local -a failed=()
    local -a skipped=()

    if [[ -z "$WORKSPACE" ]]; then
        echo "WORKSPACE is not set."
        return 1
    fi

    if [[ ! -d "$repos_dir" ]]; then
        printf "Repos directory not found: %s\n" "$repos_dir"
        return 1
    fi

    for repo in "$repos_dir"/*(/N); do
        repo_name="${repo:t}"

        if ! git -C "$repo" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
            skipped+=("$repo_name (not a git repo)")
            continue
        fi

        ((git_repo_count++))
        printf "\n\033[1;34m%s\033[0m\n" "$repo_name"

        current_branch=$(git -C "$repo" symbolic-ref --quiet --short HEAD 2>/dev/null)
        if [[ -z "$current_branch" ]]; then
            printf "  Skipping: detached HEAD.\n"
            skipped+=("$repo_name (detached HEAD)")
            continue
        fi

        target_branch=""
        remote_head=$(git -C "$repo" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null)
        if [[ -n "$remote_head" ]]; then
            target_branch="${remote_head#origin/}"
        else
            for candidate in main master develop; do
                if git -C "$repo" show-ref --verify --quiet "refs/remotes/origin/${candidate}"; then
                    target_branch="$candidate"
                    break
                fi
            done
        fi

        if [[ -z "$target_branch" ]]; then
            printf "  Skipping: could not determine the remote default branch.\n"
            skipped+=("$repo_name (unknown origin default branch)")
            continue
        fi

        stash_ref=""
        stash_name="pull-all: ${current_branch} -> ${target_branch} $(date +%Y-%m-%dT%H:%M:%S)"

        if [[ -n "$(git -C "$repo" status --short --untracked-files=all)" ]]; then
            printf "  Stashing local changes on %s\n" "$current_branch"
            if ! git -C "$repo" stash push --include-untracked -m "$stash_name" >/dev/null 2>&1; then
                printf "  Failed to stash local changes.\n"
                failed+=("$repo_name")
                continue
            fi
            stash_ref=$(git -C "$repo" stash list -1 --format="%gd")
        else
            printf "  Working tree clean on %s\n" "$current_branch"
        fi

        if [[ "$current_branch" == "$target_branch" ]]; then
            pull_output=$(git -C "$repo" pull --ff-only origin "$target_branch" 2>&1)
        else
            pull_output=$(git -C "$repo" pull --no-rebase origin "$target_branch" 2>&1)
        fi

        if [[ $? -ne 0 ]]; then
            printf "  Pull failed.\n"
            printf "%s\n" "$pull_output"
            failed+=("$repo_name")

            if [[ -n "$stash_ref" ]]; then
                if [[ ! -f "$repo/.git/MERGE_HEAD" && ! -d "$repo/.git/rebase-merge" && ! -d "$repo/.git/rebase-apply" && -z "$(git -C "$repo" diff --name-only --diff-filter=U)" ]]; then
                    apply_output=$(git -C "$repo" stash apply --index "$stash_ref" 2>&1)
                    if [[ $? -eq 0 ]]; then
                        git -C "$repo" stash drop "$stash_ref" >/dev/null 2>&1
                        printf "  Restored stashed changes after failed pull.\n"
                    else
                        printf "  Failed to restore stashed changes.\n"
                        printf "%s\n" "$apply_output"
                        conflicted+=("$repo_name")
                    fi
                else
                    printf "  Leaving the stash in place because the repo is in a conflicted state.\n"
                fi
            fi
            continue
        fi

        printf "  Pulled latest %s into %s\n" "$target_branch" "$current_branch"

        if [[ -n "$stash_ref" ]]; then
            printf "  Reapplying stashed changes\n"
            apply_output=$(git -C "$repo" stash apply --index "$stash_ref" 2>&1)
            if [[ $? -eq 0 ]]; then
                git -C "$repo" stash drop "$stash_ref" >/dev/null 2>&1
                printf "  Restored stashed changes.\n"
            else
                printf "  Stash apply has conflicts. Resolve them before continuing.\n"
                printf "%s\n" "$apply_output"
                conflicted+=("$repo_name")
                continue
            fi
        fi

        synced+=("$repo_name")
    done

    if (( git_repo_count == 0 )); then
        printf "No git repos found under %s\n" "$repos_dir"
        return 1
    fi

    printf "\n\033[1;32mFinished syncing workspace repos.\033[0m\n"

    if (( ${#synced} )); then
        printf "Synced: %s\n" "${(j:, :)synced}"
    fi

    if (( ${#conflicted} )); then
        printf "Stash conflicts: %s\n" "${(j:, :)conflicted}"
    fi

    if (( ${#failed} )); then
        printf "Pull failures: %s\n" "${(j:, :)failed}"
    fi

    if (( ${#skipped} )); then
        printf "Skipped: %s\n" "${(j:, :)skipped}"
    fi

    if (( ${#failed} || ${#conflicted} )); then
        return 1
    fi
}

# push every repo in $WORKSPACE/repos to its origin current branch
push-all() {
    emulate -L zsh
    setopt null_glob

    local repos_dir="${WORKSPACE}/repos"
    local repo repo_name current_branch push_output
    local git_repo_count=0
    local -a pushed=()
    local -a failed=()
    local -a skipped=()

    if [[ -z "$WORKSPACE" ]]; then
        echo "WORKSPACE is not set."
        return 1
    fi

    if [[ ! -d "$repos_dir" ]]; then
        printf "Repos directory not found: %s\n" "$repos_dir"
        return 1
    fi

    for repo in "$repos_dir"/*(/N); do
        repo_name="${repo:t}"

        if ! git -C "$repo" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
            skipped+=("$repo_name (not a git repo)")
            continue
        fi

        ((git_repo_count++))
        printf "\n\033[1;34m%s\033[0m\n" "$repo_name"

        current_branch=$(git -C "$repo" symbolic-ref --quiet --short HEAD 2>/dev/null)
        if [[ -z "$current_branch" ]]; then
            printf "  Skipping: detached HEAD.\n"
            skipped+=("$repo_name (detached HEAD)")
            continue
        fi

        if [[ -n "$(git -C "$repo" diff --name-only --diff-filter=U)" ]]; then
            printf "  Skipping: unresolved merge conflicts.\n"
            skipped+=("$repo_name (merge conflicts)")
            continue
        fi

        push_output=$(git -C "$repo" push origin "$current_branch" 2>&1)
        if [[ $? -ne 0 ]]; then
            printf "  Push failed.\n"
            printf "%s\n" "$push_output"
            failed+=("$repo_name")
            continue
        fi

        printf "  Pushed %s\n" "$current_branch"
        pushed+=("$repo_name")
    done

    if (( git_repo_count == 0 )); then
        printf "No git repos found under %s\n" "$repos_dir"
        return 1
    fi

    printf "\n\033[1;32mFinished pushing workspace repos.\033[0m\n"

    if (( ${#pushed} )); then
        printf "Pushed: %s\n" "${(j:, :)pushed}"
    fi

    if (( ${#failed} )); then
        printf "Push failures: %s\n" "${(j:, :)failed}"
    fi

    if (( ${#skipped} )); then
        printf "Skipped: %s\n" "${(j:, :)skipped}"
    fi

    if (( ${#failed} )); then
        return 1
    fi
}
