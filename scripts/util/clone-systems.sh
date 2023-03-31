#!/bin/bash
# ./clone-systems.sh
# clones system repositories using git

load-config

add-system(system, url) {
    local subject="git-clone: $system"
    if [[ ! -d "$(input-directory)/$system" ]]; then
        log "$subject" "$(echo-progress clone)"
        git clone "$url" "$(input-directory)/$system"
        log "$subject" "$(echo-done)"
    else
        log "$subject" "$(echo-skip)"
    fi
}

load-subjects