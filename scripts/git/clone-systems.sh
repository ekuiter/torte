#!/bin/bash
# ./clone-systems.sh
# clones system repositories using git

add-system() {
    local system=$1
    local url=$2
    require-value system url
    if [[ ! -d "$(input-directory)/$system" ]]; then
        echo "Cloning system $system"
        git clone "$url" "$(input-directory)/$system"
    else
        echo "Skipping clone for system $system"
    fi
}

# shellcheck source=../../scripts/torte.sh
source torte.sh load-subjects