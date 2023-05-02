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
    source-script "$SCRIPTS_DIRECTORY/_experiment.sh"
}

# removes all output files for the experiment
# does not touch input files or Docker images
command-clean() {
    rm-safe "$OUTPUT_DIRECTORY"
}

# runs the experiment
command-run() {
    mkdir -p "$INPUT_DIRECTORY"
    mkdir -p "$OUTPUT_DIRECTORY"
    clean "$DOCKER_PREFIX"
    mkdir -p "$(output-directory "$DOCKER_PREFIX")"
    cp "$SCRIPTS_DIRECTORY/_experiment.sh" "$(output-directory "$DOCKER_PREFIX")/_experiment.sh"
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

# runs the experiment on a remote server
# removes previous experiment results and reinstalls evaluation scripts
# shellcheck disable=SC2029
command-run-remote(host, directory=.) {
    require-command ssh scp
    scp -r "$SCRIPTS_DIRECTORY/_experiment.sh" "$host:$directory"
    local cmd="(cd $directory;"
    cmd+="  bash _experiment.sh rm-safe $OUTPUT_DIRECTORY $DOCKER_PREFIX; "
    cmd+="  screen -dmSL $DOCKER_PREFIX bash _experiment.sh; "
    cmd+=");"
    cmd+="alias $DOCKER_PREFIX-stop='screen -X -S $DOCKER_PREFIX kill; bash $directory/_experiment.sh stop'; "
    ssh "$host" "$cmd"
    echo "$DOCKER_PREFIX is now running on $host, opening an SSH session."
    echo "To view its output, run:"
    echo "  $DOCKER_PREFIX (Ctrl+a d to detach)"
    echo "To stop it, run:"
    echo "  $DOCKER_PREFIX-stop"
    cmd=""
    cmd+="$DOCKER_PREFIX() { screen -x $DOCKER_PREFIX; };"
    cmd+="$DOCKER_PREFIX-stop() { screen -X -S $DOCKER_PREFIX kill; bash $directory/_experiment.sh stop; };"
    cmd+="export -f $DOCKER_PREFIX $DOCKER_PREFIX-stop;"
    cmd+="/bin/bash"
    ssh -t "$host" "$cmd"
}

# downloads results from the remote server
command-copy-remote(host, directory=.) {
    require-command scp
    scp -r "$host:$directory/$OUTPUT_DIRECTORY" "$OUTPUT_DIRECTORY-$host-$(date "+%Y-%m-%d")"
}