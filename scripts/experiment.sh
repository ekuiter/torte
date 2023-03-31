#!/bin/bash

# prepares an experiment by loading its file given by the environment variable EXPERIMENT_FILE
# this has no effect besides defining variables and functions
# sets several global variables
load-experiment() {
    if [[ -z $DOCKER_RUNNING ]]; then
        EXPERIMENT_FILE=${EXPERIMENT_FILE:-input/experiment.sh}
    else
        EXPERIMENT_FILE=${EXPERIMENT_FILE:-_experiment.sh}
    fi
    if [[ ! -f $EXPERIMENT_FILE ]]; then
        echo "Please provide an experiment in $EXPERIMENT_FILE."
        exit 1
    fi
    # shellcheck source=../input/experiment.sh
    source "$EXPERIMENT_FILE"
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
load-subjects() { # todo: remove
    experiment-subjects
}

# removes all output files for the experiment
# does not touch input files or Docker images
clean-experiment() {
    require-host
    rm-safe "$OUTPUT_DIRECTORY"
}

# runs the experiment
run-experiment() {
    require-host
    require-command docker
    mkdir -p "$OUTPUT_DIRECTORY"
    clean "$DOCKER_PREFIX"
    mkdir -p "$(output-directory "$DOCKER_PREFIX")"
    experiment-stages \
        > >(write-log "$(output-log "$DOCKER_PREFIX")") \
        2> >(write-all "$(output-err "$DOCKER_PREFIX")" >&2)
}

# stops the experiment
stop-experiment() {
    readarray -t containers < <(docker ps | awk '$2 ~ /^'"$DOCKER_PREFIX"'_/ {print $1}')
    if [[ ${#containers[@]} -gt 0 ]]; then
        docker kill "${containers[@]}"
    fi
}
