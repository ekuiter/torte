#!/bin/bash
# ./clone-systems.sh
# clones system repositories using git

load-config

add-system(system, url) {
    local subject="git-clone: $system"
    if [[ ! -d "$(input-directory)/$system" ]]; then
        log "$subject" "$(yellow-color)clone"
        git clone "$url" "$(input-directory)/$system"
        log "$subject" "$(green-color)done"
    else
        log "$subject" "$(blue-color)skip"
    fi
}

load-subjects