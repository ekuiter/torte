#!/bin/bash
set -e

push_repository() {
    local directory=$1
    local remote=$2
    if [[ ! -d $directory ]]; then
        echo "Skipping missing repository: $directory"
        return
    fi
    git -C "$directory" remote remove origin 2>/dev/null || true
    git -C "$directory" remote add origin "$remote"
    git -C "$directory" push origin --all
    git -C "$directory" push origin --tags
}

push_linux_repository() {
    local directory=$1
    local remote=$2
    local batch_size=20000
    if [[ ! -d $directory ]]; then
        echo "Skipping missing repository: $directory"
        return
    fi
    git -C "$directory" remote remove origin 2>/dev/null || true
    git -C "$directory" remote add origin "$remote"
    local branch range n i h
    branch=$(git -C "$directory" rev-parse --abbrev-ref HEAD)
    if git -C "$directory" show-ref --quiet --verify "refs/remotes/origin/$branch"; then
        range="origin/$branch..HEAD"
    else
        range=HEAD
    fi
    n=$(git -C "$directory" log --first-parent --format=format:x "$range" | wc -l)
    for i in $(seq "$n" -"$batch_size" 1); do
        h=$(git -C "$directory" log --first-parent --reverse --format=format:%H --skip "$i" -n1)
        echo "Pushing $directory@$h..."
        git -C "$directory" push --force origin "$h:refs/heads/$branch"
    done
    git -C "$directory" push --force origin "HEAD:refs/heads/$branch"
    git -C "$directory" push --force origin --tags
}

push_linux_repository stages/1_clone_systems/linux git@github.com:ekuiter/torte-linux.git
push_repository stages/1_clone_systems/busybox git@github.com:ekuiter/torte-busybox.git
