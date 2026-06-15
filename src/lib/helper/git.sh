#!/bin/bash
# helpers for working with Git

# remove (un-)staged changes and untracked files
git-clean(directory=.) {
    rm-safe "$directory/.git/index.lock"
    git -C "$directory" reset -q --hard > /dev/null
    git -C "$directory" clean -q -dfx > /dev/null
}

# clean and checkout a revision
git-checkout(revision, directory=.) {
    echo "Checking out $revision in $directory"
    git-clean "$directory"
    git -C "$directory" checkout -q -f "$revision" > /dev/null
}

# returns committer date of given revision as Unix timestamp
git-timestamp(system, revision) {
    git -C "$(input-directory)/$system" log -1 --pretty=%ct "$revision"
}

# returns the commit message of a given revision
git-commit-message(system, revision) {
    git -C "$(input-directory)/$system" log -1 --format=%B "$revision"
}

# list all tags in version order
git-tags(system) {
    if [[ ! -d $(input-directory)/$system ]]; then
        return
    fi
    git -C "$(input-directory)/$system" tag | sort -V
}

# lists commits on a branch, oldest first
git-commits(system, branch=master) {
    if [[ ! -d $(input-directory)/$system ]]; then
        return
    fi
    git -C "$(input-directory)/$system" log "$branch" --format="%h" --reverse
}

# lists commits on a branch that touched any given paths, oldest first
git-commits-touching(system, branch=master, paths...) {
    assert-array paths
    if [[ ! -d $(input-directory)/$system ]]; then
        return
    fi
    git -C "$(input-directory)/$system" log "$branch" --format="%h" --reverse -- "${paths[@]}"
}

# sample commits in a given interval
git-sample-commits(system, interval, branch=master) {
    if [[ ! -d $(input-directory)/$system ]]; then
        return
    fi
    local last_timestamp current_timestamp now_timestamp
    git-checkout "$branch" "$(input-directory)/$system" > /dev/null
    timestamp=$(git-timestamp "$system" "$(git -C "$(input-directory)/$system" log --format="%h" | tail -1)")
    last_timestamp=$timestamp
    now_timestamp=$(date +%s)
    local N=20
    while [[ $timestamp -lt $now_timestamp ]]; do
        git -C "$(input-directory)/$system" --no-pager log -1 --format="%h" --since "$last_timestamp" --until "$timestamp" &
        last_timestamp=$timestamp
        ((timestamp+="$interval"))
        if [[ $(jobs -r -p | wc -l) -ge $N ]]; then wait -n; fi
    done
}
