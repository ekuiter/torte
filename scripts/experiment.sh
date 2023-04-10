#!/bin/bash

# prepares an experiment by loading its file
# this has no effect besides defining variables and functions
# sets several global variables
load-experiment(experiment_file=experiments/default.sh) {
    if is-host; then
        if [[ ! -f $experiment_file ]]; then
            error-help "Please provide an experiment in $experiment_file."
        fi
        cp "$experiment_file" "$SCRIPTS_DIRECTORY/_experiment.sh"
    fi
    # shellcheck source=../experiments/experiment.sh
    source "$SCRIPTS_DIRECTORY/_experiment.sh"
}

# removes all output files for the experiment
# does not touch input files or Docker images
command-clean() {
    rm-safe "$OUTPUT_DIRECTORY"
}

# runs the experiment
command-run() {
    mkdir -p "$OUTPUT_DIRECTORY"
    clean "$DOCKER_PREFIX"
    mkdir -p "$(output-directory "$DOCKER_PREFIX")"
    experiment-stages \
        > >(write-log "$(output-log "$DOCKER_PREFIX")") \
        2> >(write-all "$(output-err "$DOCKER_PREFIX")" >&2)
}

# stops the experiment
command-stop() {
    readarray -t containers < <(docker ps | tail -n+2 | awk '$2 ~ /^'"$DOCKER_PREFIX"'_/ {print $1}')
    if [[ ${#containers[@]} -gt 0 ]]; then
        docker kill "${containers[@]}"
    fi
}