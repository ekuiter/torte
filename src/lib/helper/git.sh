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

# sample commits in a given interval, starting at the oldest commit
# to stop sampling early, pass a commit hash as the branch argument
git-sample-commits(system, interval, branch=master) {
    if [[ ! -d $(input-directory)/$system ]]; then
        return
    fi
    local timestamp last_timestamp current_timestamp end_timestamp
    git-checkout "$branch" "$(input-directory)/$system" > /dev/null
    timestamp=$(git-timestamp "$system" "$(git -C "$(input-directory)/$system" log --format="%h" | tail -1)")
    last_timestamp=$timestamp
    end_timestamp=$(git-timestamp "$system" HEAD)
    local N=20
    while [[ $timestamp -lt $end_timestamp ]]; do
        git -C "$(input-directory)/$system" --no-pager log -1 --format="%h" --since "$last_timestamp" --until "$timestamp" &
        last_timestamp=$timestamp
        ((timestamp+="$interval"))
        if [[ $(jobs -r -p | wc -l) -ge $N ]]; then wait -n; fi
    done
}

# for a given list of revisions on stdin, returns the latest revision per year
# uses commit dates, prints revisions in year order, and omits years without candidates
git-last-revision-per-year(system, from, to) {
    if [[ ! $from =~ ^[1-9][0-9]{3}$ || ! $to =~ ^[1-9][0-9]{3}$ ]] \
        || [[ $from -gt $to ]]; then
        error "Invalid year range $from-$to."
    fi
    if [[ ! -d $(input-directory)/$system ]]; then
        return
    fi
    local revision timestamp year
    local -A revisions_by_year=() timestamps_by_year=()
    while IFS= read -r revision || [[ -n $revision ]]; do
        [[ -z $revision ]] && continue
        timestamp=$(git-timestamp "$system" "$revision") || return
        year=$(date -u -d "@$timestamp" +%Y) || return
        if [[ $year -ge $from && $year -le $to ]] \
            && [[ -z ${timestamps_by_year[$year]} || $timestamp -ge ${timestamps_by_year[$year]} ]]; then
            revisions_by_year[$year]=$revision
            timestamps_by_year[$year]=$timestamp
        fi
    done
    for ((year=from; year<=to; year++)); do
        if [[ -n ${revisions_by_year[$year]} ]]; then
            echo "${revisions_by_year[$year]}"
        fi
    done
}