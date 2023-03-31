#!/bin/bash

# prepares an experiment by loading the given config file
# this has no effect besides defining variables and functions
# sets several global variables
load-config() {
    if [[ -n $CONFIG_FILE ]]; then
        return
    fi
    if [[ -z $DOCKER_RUNNING ]]; then
        CONFIG_FILE=${1:-input/config.sh}
    else
        CONFIG_FILE=${1:-_config.sh}
    fi
    if [[ ! -f $CONFIG_FILE ]]; then
        echo "Please provide a config file in $CONFIG_FILE."
        exit 1
    fi
    # shellcheck source=../input/config.sh
    source "$CONFIG_FILE"
     # path to system repositories
    INPUT_DIRECTORY=${INPUT_DIRECTORY:-input}
    # path to resulting outputs, created if necessary
    OUTPUT_DIRECTORY=${OUTPUT_DIRECTORY:-output}
    # y if building Docker images should be skipped, useful for loading imported images
    SKIP_DOCKER_BUILD=${SKIP_DOCKER_BUILD:-}
     # memory limit in GiB for running Docker containers and other tools, should be at least 2 GiB
    MEMORY_LIMIT=${MEMORY_LIMIT:-$(($(sed -n '/^MemTotal:/ s/[^0-9]//gp' /proc/meminfo)/1024/1024))}
    # y if every stage should be forced to run regardless of whether is is already done
    FORCE_RUN=${FORCE_RUN:-}
    # y if console output should be verbose
    VERBOSE=${VERBOSE:-}
}

# loads a config file and adds all experiment subjects
load-subjects(config_file=) {
    load-config "$config_file"
    experiment-subjects
}

# removes all output files for the gives experiment
# does not touch input files or Docker images
clean-experiment(config_file=) {
    require-host
    load-config "$config_file"
    rm-safe "$OUTPUT_DIRECTORY"
}

# runs the gives experiment
run-experiment(config_file=) {
    require-host
    require-command docker
    load-config "$config_file"
    mkdir -p "$OUTPUT_DIRECTORY"
    clean "$DOCKER_PREFIX"
    mkdir -p "$(output-directory "$DOCKER_PREFIX")"
    experiment-stages \
        > >(write-log "$(output-log "$DOCKER_PREFIX")") \
        2> >(write-all "$(output-err "$DOCKER_PREFIX")" >&2)
}

# stops all running experiments
stop-experiments() {
    readarray -t containers < <(docker ps | awk '$2 ~ /^'"$DOCKER_PREFIX"'_/ {print $1}')
    if [[ ${#containers[@]} -gt 0 ]]; then
        docker kill "${containers[@]}"
    fi
}
