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
    clean "$TOOL"
    mkdir -p "$(output-directory "$TOOL")"
    cp "$SCRIPTS_DIRECTORY/_experiment.sh" "$(output-directory "$TOOL")/_experiment.sh"
    define-stage-helpers
    if grep -q '^\s*debug\s*$' "$SCRIPTS_DIRECTORY/_experiment.sh"; then
        experiment-stages
    else
        experiment-stages \
            > >(write-log "$(output-log "$TOOL")") \
            2> >(write-all "$(output-err "$TOOL")" >&2)
    fi
}

# stops the experiment
command-stop() {
    readarray -t containers < <(docker ps | tail -n+2 | awk '$2 ~ /^'"$TOOL"'_/ {print $1}')
    if [[ ${#containers[@]} -gt 0 ]]; then
        docker kill "${containers[@]}"
    fi
}

# runs the experiment on a remote server
# removes previous experiment results and reinstalls evaluation scripts
# shellcheck disable=SC2029
command-run-remote(host, file=experiment.tar.gz, directory=.) {
    require-command ssh scp
    scp -r "$file" "$host:$directory"
    local cmd="(cd $directory;"
    cmd+="  bash _experiment.sh rm-safe $TOOL $OUTPUT_DIRECTORY; "
    cmd+="  tar xzvf $(basename "$file"); "
    cmd+="  rm $(basename "$file"); "
    cmd+="  screen -dmSL $TOOL bash _experiment.sh; "
    cmd+=");"
    ssh "$host" "$cmd"
    echo "$TOOL is now running on $host, opening an SSH session."
    echo "To view its output, run $TOOL (Ctrl+a d to detach)."
    echo "To stop it, run $TOOL-stop."
    cmd=""
    cmd+="$TOOL() { screen -x $TOOL; };"
    cmd+="$TOOL-stop() { screen -X -S $TOOL kill; bash $directory/_experiment.sh stop; };"
    cmd+="export -f $TOOL $TOOL-stop;"
    cmd+="/bin/bash"
    ssh -t "$host" "$cmd"
}

# downloads results from the remote server
command-copy-remote(host, directory=.) {
    require-command rsync
    rsync -av "$host:$directory/$OUTPUT_DIRECTORY/" "$OUTPUT_DIRECTORY-$host-$(date "+%Y-%m-%d")"
}