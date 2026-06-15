#!/bin/bash
# functions for working with Git repositories and statistics

CLONE_DONE_FILE=".clone_done" # file indicating clone completion

# clones system repositories using git and applies the requested repository transform(s), if any
clone-systems() {
    # the first add-system call for a system wins over subsequent calls
    # this can be used to override which transforms to use, for example in an experiment file
    add-system(system, url, fork_url=, transform...) {
        log "git-clone: $system"
        local directory clone_done_file
        directory="$(output-directory)/$system"
        clone_done_file="$directory/$CLONE_DONE_FILE"
        if [[ -f $clone_done_file ]] || should-skip add-system "" "$system"; then
            log "" "$(echo-skip)"
            return
        fi
        rm-safe "$directory"
        compile-hook pre-clone-hook
        pre-clone-hook "$system" "$url"
        log "" "$(echo-progress clone)"
        # if a prepared fork exists and fork cloning is enabled, use it instead of regenerating the transform
        # CLONE_FORKS= forces rerunning transform(s) locally
        if ! is-array-empty transform && [[ -n $fork_url ]] && [[ -n $CLONE_FORKS ]]; then
            git clone "$fork_url" "$directory"
        else
            git clone "$url" "$directory"
            compile-hook post-clone-hook
            post-clone-hook "$system" "${transform[@]}"
        fi
        : > "$clone_done_file"
        if ! is-array-empty transform; then
            printf '%s\n' "${transform[@]}" > "$clone_done_file"
        fi
        log "" "$(echo-done)"
    }

    experiment-systems

    # allow adding additional dependencies outside of experiment-systems
    compile-hook post-experiment-systems-hook
    post-experiment-systems-hook
}

# rewrites a repository to generated KConfig commits using a system-specific generator
generate-kconfig-commits(system, generator, branch=master, change_globs...) {
    assert-value system generator
    if ! has-function "$generator"; then
        error "Generator $generator is not defined."
    fi
    local input_directory
    input_directory="$(input-directory)/$system"
    log generate-kconfig-commits

    # create a temporary Git repository for the generated KConfig history
    local output_directory
    output_directory=$(mktemp -d "$(output-directory)/.${system}.XXXXXX")
    git -C "$output_directory" init -b "$branch" -q
    echo "*.log" >> "$output_directory/.gitignore"
    echo "*.err" >> "$output_directory/.gitignore"

    # iterate over the source repository from oldest to newest commit
    local i n
    i=0
    n=$(git -C "$input_directory" log "$branch" --format="%h" | wc -l)
    while read -r revision; do
        ((i+=1))
        local timestamp
        timestamp=$(git-timestamp "$system" "$revision")

        # generate the KConfig snapshot for the current source revision
        find "$output_directory" -mindepth 1 \
            -path "$output_directory/.git" -prune -o \
            -exec rm -rf {} + 2>/dev/null || true
        git-checkout "$revision" "$input_directory" > /dev/null
        "$generator" "$system" "$input_directory" "$output_directory" "$revision"

        # commit the snapshot only if it is the first one or changed relevant files
        git -C "$output_directory" add -A
        if [[ $i -eq 1 ]] || ! git -C "$output_directory" diff --staged --quiet -- "${change_globs[@]}"; then
            GIT_AUTHOR_DATE=$timestamp GIT_COMMITTER_DATE=$timestamp \
                git -C "$output_directory" commit -q -m "$revision" --date "$timestamp" >/dev/null || true
        fi
        if [ $((i % 100)) -eq 1 ]; then
            log "" "$(echo-progress "$((i*100/n))%")"
        fi
    done < <(git -C "$input_directory" log "$branch" --format="%h" | tac)
    log "" "$(echo-done)"

    # replace the original clone with the generated KConfig history
    rm-safe "$input_directory"
    mv "$output_directory" "$input_directory"
}

# checks whether a cloned system was prepared with a given transform
system-has-transform(system, transform) {
    grep -qx "$transform" "$(input-directory)/$system/$CLONE_DONE_FILE" 2>/dev/null
}

# counts number of source lines of codes using cloc
read-statistics(options=) {
    STATISTICS_OPTIONS=$options

    add-revision(system, revision) {
        revision=$(revision-without-context "$revision")
        log "read-statistics: $system@$revision" "$(echo-progress read)"
        if grep -q "^$system,$revision," "$(output-path date.csv)"; then
            log "" "$(echo-skip)"
            return
        fi
        local time
        time=$(git -C "$(input-directory)/$system" --no-pager log -1 -s --format=%ct "$revision")
        local date
        date=$(date -d "@$time" +"%Y-%m-%d")
        echo "$system,$revision,$time,$date" >> "$(output-path date.csv)"
        if [[ $STATISTICS_OPTIONS != skip-sloc ]]; then
            local sloc_file
            sloc_file=$(output-path "$system" "$revision.txt")
            push "$(input-directory)/$system"
            cloc --git "$revision" > "$sloc_file"
            pop
            local sloc
            sloc=$(grep ^SUM < "$sloc_file" | tr -s ' ' | cut -d' ' -f5)
            echo "$system,$revision,$sloc" >> "$(output-path sloc.csv)"
        else
            echo "$system,$revision,NA" >> "$(output-path sloc.csv)"
        fi
        log "" "$(echo-done)"
    }

    echo system,revision,committer_date_unix,committer_date_readable > "$(output-path date.csv)"
    echo system,revision,source_lines_of_code > "$(output-path sloc.csv)"
    experiment-systems
    join-tables "$(output-path date.csv)" "$(output-path sloc.csv)" > "$(output-csv)"
}
