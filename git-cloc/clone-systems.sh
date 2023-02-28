#!/bin/bash

# ./clone-systems.sh
# clones system repositories using git

source _evaluate.sh init

add-system() {
    local system=$1
    local url=$2
    require-value system url
    if [[ ! -d "$docker_input_directory/$system" ]]; then
        echo "Cloning system $system"
        git clone $url $docker_input_directory/$system
    else
        echo "Skipping clone for system $system"
    fi
}

source _evaluate.sh load-experiment