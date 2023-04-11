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
command-ssh(host, command=ssh, directory=.) {
    require-command ssh scp

    run-ssh(arguments...) {
        # shellcheck disable=SC2086
        $command "$host" "${arguments[@]}"
    }

    run-scp(file) {
        # shellcheck disable=SC2086
        scp -qr "$file" "$host:$directory"
    }

    run-scp "$SCRIPTS_DIRECTORY/_experiment.sh"
    run-ssh "(cd $directory; screen -dmS $DOCKER_PREFIX bash _experiment.sh)"
    echo "$DOCKER_PREFIX is now running on $host, opening an SSH session."
    echo "To view its output, run:"
    echo "  screen -x $DOCKER_PREFIX (Ctrl+a d to detach)"
    echo "To stop it, run:"
    echo "  screen -x $DOCKER_PREFIX (Ctrl+a k y to kill)"
    echo "  bash _experiment.sh stop"
    $command "$host"
}