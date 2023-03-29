#!/bin/bash
# ./clone-systems.sh
# clones system repositories using git

load-config

add-system(system, url) {
    local subject="git-clone: $system"
    if [[ ! -d "$(input-directory)/$system" ]]; then
        log "$subject" "$(echo-yellow clone)"
        git clone "$url" "$(input-directory)/$system"
        log "$subject" "$(echo-green "done")"
    else
        log "$subject" "$(echo-blue skip)"
    fi
}

load-subjects