#!/bin/bash
# runs experiments

# where to store the preprocessed experiment file
SRC_EXPERIMENT_DIRECTORY=$SRC_DIRECTORY/experiment
SRC_EXPERIMENT_FILE=$SRC_EXPERIMENT_DIRECTORY/experiment.sh

# returns the path to a given experiment file
experiment-file(experiment_file=default) {
    if [[ -f $experiment_file ]]; then
        echo "$experiment_file"
    elif [[ -f $TOOL_DIRECTORY/experiments/$experiment_file/experiment.sh ]]; then
        echo "$TOOL_DIRECTORY/experiments/$experiment_file/experiment.sh"
    fi
}

# returns the path to a given payload file
payload-file(payload_file) {
    payload_file=$SRC_EXPERIMENT_DIRECTORY/$payload_file
    [[ -f $payload_file ]] && echo "$payload_file"
}

# adds a new payload file
# these are files of interest that reside besides the experiment file, such as Jupyter notebooks
add-payload-file(payload_file) {
    original_payload_file=$(dirname "$ORIGINAL_EXPERIMENT_FILE")/$payload_file
    src_payload_file=$SRC_EXPERIMENT_DIRECTORY/$payload_file
    if [[ $payload_file == "$(basename "$ORIGINAL_EXPERIMENT_FILE")" ]]; then
        error-help "The payload file $payload_file cannot be the experiment file."
    # elif [[ ! -f $original_payload_file ]] && [[ -n $TORTE_EXPERIMENT ]] && [[ -f $(dirname "$(experiment-file "$TORTE_EXPERIMENT")")/$payload_file ]]; then
    #     # this addresses the corner case where the experiment file has been obtained with the one-liner from the README file (which sets TORTE_EXPERIMENT)
    #     # in that case, we obtain the payload from this project's repository
    #     original_payload_file=$(dirname "$(experiment-file "$TORTE_EXPERIMENT")")/$payload_file
    elif [[ ! -f $original_payload_file ]]; then
        error-help "The requested payload file $payload_file does not exist and cannot be added."
    fi
    mkdir -p "$SRC_EXPERIMENT_DIRECTORY"
    cp "$original_payload_file" "$src_payload_file"
}

# prepares an experiment by loading its file
# this has no effect besides defining (global) variables and functions
load-experiment(experiment_file=default) {
    if is-host; then
        experiment_file=$(experiment-file "$experiment_file")
        if [[ -z $experiment_file ]]; then
            error-help "Please provide an experiment in $experiment_file."
        fi
        ORIGINAL_EXPERIMENT_FILE=$experiment_file
        if [[ ! $experiment_file -ef $SRC_EXPERIMENT_FILE ]]; then
            rm-safe "$SRC_EXPERIMENT_DIRECTORY"
            mkdir -p "$SRC_EXPERIMENT_DIRECTORY"
            cp "$experiment_file" "$SRC_EXPERIMENT_FILE"
        fi
    fi
    source-script "$SRC_EXPERIMENT_FILE"
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
    clean "$TOOL"s
    mkdir -p "$(output-directory "$TOOL")"
    cp -R "$SRC_EXPERIMENT_DIRECTORY" "$(output-directory "$TOOL")"
    define-stage-helpers
    if grep -q '^\s*debug\s*$' "$SRC_EXPERIMENT_FILE"; then
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
command-run-remote(host, file=experiment.tar.gz, directory=., sudo=) {
    assert-command ssh scp
    if [[ $sudo == y ]]; then
        sudo=sudo
    fi
    scp -r "$file" "$host:$directory"
    local cmd="(cd $directory;"
    cmd+="  tar xzvf $(basename "$file"); "
    cmd+="  rm $(basename "$file"); "
    cmd+="  screen -dmSL $TOOL $sudo bash experiment/experiment.sh; "
    cmd+=");"
    ssh "$host" "$cmd"
    echo "$TOOL is now running on $host, opening an SSH session."
    echo "To view its output, run $TOOL (Ctrl+a d to detach)."
    echo "To stop it, run $TOOL-stop."
    cmd=""
    cmd+="$TOOL() { screen -x $TOOL; };"
    cmd+="$TOOL-stop() { screen -X -S $TOOL kill; bash $directory/experiment/experiment.sh stop; };"
    cmd+="export -f $TOOL $TOOL-stop;"
    cmd+="/bin/bash"
    ssh -t "$host" "$cmd"
}

# downloads results from the remote server
command-copy-remote(host, directory=.) {
    assert-command rsync
    rsync -av "$host:$directory/$OUTPUT_DIRECTORY/" "$OUTPUT_DIRECTORY-$host-$(date "+%Y-%m-%d")"
}

# installs a Docker image on a remote server
# shellcheck disable=SC2029
command-install-remote(host, image, directory=.) {
    ssh "$host" docker image rm "${TOOL}_$image" 2>/dev/null || true
    docker save "${TOOL}_$image" | gzip -c | ssh "$host" "cat > $directory/$image.tar.gz"
    ssh "$host" docker load -i "$directory/$image.tar.gz"
}