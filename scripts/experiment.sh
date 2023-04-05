#!/bin/bash

# prepares an experiment by loading its file given by the environment variable EXPERIMENT_FILE
# this has no effect besides defining variables and functions
# sets several global variables
load-experiment() {
    if is-host; then
        EXPERIMENT_FILE=${EXPERIMENT_FILE:-input/experiment.sh}
        cp "$EXPERIMENT_FILE" "$SCRIPTS_DIRECTORY/_experiment.sh"
    else
        EXPERIMENT_FILE=_experiment.sh
    fi
    if [[ ! -f $EXPERIMENT_FILE ]]; then
        echo "Please provide an experiment in $EXPERIMENT_FILE."
        exit 1
    fi
    # shellcheck source=../input/experiment.sh
    source "$SCRIPTS_DIRECTORY/_experiment.sh"
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
    mkdir -p "$OUTPUT_DIRECTORY"
    clean "$DOCKER_PREFIX"
    mkdir -p "$(output-directory "$DOCKER_PREFIX")"
    experiment-stages \
        > >(write-log "$(output-log "$DOCKER_PREFIX")") \
        2> >(write-all "$(output-err "$DOCKER_PREFIX")" >&2)
}

# stops the experiment
stop-experiment() {
    readarray -t containers < <(docker ps | tail -n+2 | awk '$2 ~ /^'"$DOCKER_PREFIX"'_/ {print $1}')
    if [[ ${#containers[@]} -gt 0 ]]; then
        docker kill "${containers[@]}"
    fi
}
