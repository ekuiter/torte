#!/bin/bash

# runs a stage of some experiment in a Docker container
# reads the global CONFIG_FILE variable
run-stage() {
    local stage=$1
    local dockerfile=$2
    local input_directory=$3
    require-host
    require-value CONFIG_FILE stage dockerfile input_directory
    exec > >(append "$(output-log torte)")
    exec 2> >(append "$(output-err torte)" >&2)
    local flags=
    if [[ $# -lt 4 ]]; then
        command=(/bin/bash)
        flags=-it
    else
        command=("${@:4}")
    fi
    if [[ ! -f $(output-log "$stage") ]]; then
        echo "Running stage $stage"
        rm-safe "$(output-prefix "$stage")"/ "$(output-prefix "$stage")".*
        if [[ $SKIP_DOCKER_BUILD != y ]]; then
            cp "$CONFIG_FILE" "$SCRIPTS_DIRECTORY/_config.sh"
            docker build \
                -f "$dockerfile"\
                -t "${DOCKER_PREFIX}_$stage" \
                --ulimit nofile=20000:20000 \
                "$SCRIPTS_DIRECTORY"
        fi
        mkdir -p "$(output-directory "$stage")"
        docker run $flags \
            -v "$PWD/$input_directory:$DOCKER_INPUT_DIRECTORY" \
            -v "$PWD/$(output-directory "$stage"):$DOCKER_OUTPUT_DIRECTORY" \
            -e DOCKER_RUNNING=y \
            --rm \
            "${DOCKER_PREFIX}_$stage" \
            "${command[@]}" \
            > >(append "$(output-log "$stage")") \
            2> >(append "$(output-err "$stage")" >&2)
        copy-output-files "$stage"
        rmdir --ignore-fail-on-non-empty "$(output-directory "$stage")"
        # todo: delete err file if empty
    else
        echo "Skipping stage $stage"
    fi
}

# merges the output files of two or more stages in a new stage
run-aggregate-stage() {
    local new_stage=$1
    local arguments=("${@:2}")
    require-host
    require-value new_stage arguments
    run-stage "$new_stage" scripts/git/Dockerfile "$OUTPUT_DIRECTORY" ./aggregate.sh "${arguments[@]}"
}

# runs a stage a given number of time and merges the output files in a new stage
run-iterated-stage() {
    local iterations=$1
    local file_field=$2
    local stage_field=$3
    local new_stage=$4
    local arguments=("${@:5}")
    require-host
    require-value iterations file_field stage_field new_stage arguments
    local stages=()
    for i in $(seq "$iterations"); do
        local stage="${new_stage}_$i"
        stages+=("$stage")
        run-stage "$stage" "${arguments[@]}"
    done
    local common_fields
    common_fields=$(table-fields-except "$(output-csv "${new_stage}_1")" "$file_field")
    run-aggregate-stage "$new_stage" "$file_field" "$stage_field" "$common_fields" "${stages[@]}"
}

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
    require-variable CONFIG_FILE INPUT_DIRECTORY OUTPUT_DIRECTORY SKIP_DOCKER_BUILD
}

# loads a config file and adds all experiment subjects
load-subjects() {
    load-config "$1"
    experiment-subjects
}

# removes all output files specified by the given config file
# does not touch input files or Docker images
clean() {
    require-host
    load-config "$1"
    rm-safe "$OUTPUT_DIRECTORY"
}

# runs the experiment defined in the given config file
run() {
    require-host
    require-command docker
    load-config "$1"
    mkdir -p "$OUTPUT_DIRECTORY"
    rm-safe "$(output-prefix torte)".*
    experiment-stages
}

# stops a running experiment
stop() {
    readarray -t containers < <(docker ps | awk '$2 ~ /^eval_/ {print $1}')
    if [[ ${#containers[@]} -gt 0 ]]; then
        docker kill "${containers[@]}"
    fi
}