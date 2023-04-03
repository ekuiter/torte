#!/bin/bash
# ./clone-systems.sh
# clones system repositories using git

add-system(system, url) {
    local subject=""
    log "git-clone: $system"
    if [[ ! -d "$(input-directory)/$system" ]]; then
        log "" "$(echo-progress clone)"
        git clone "$url" "$(input-directory)/$system"
        log "" "$(echo-done)"
    else
        log "" "$(echo-skip)"
    fi
}

load-subjects