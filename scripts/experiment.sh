#!/bin/bash

# returns whether there is an output log for the given experiment stage
has-stage-log() {
    local stage=$1
    require-host
    require-value stage
    [[ -f $(output-log "$stage") ]]
}

has-stage-output() {
    local stage=$1
    require-host
    require-value stage
    has-stage-log "$stage" && [[ -d $(output-directory "$stage") ]]
}

# requires that there is cached output for the given experiment stage
require-stage-output() {
    local stage=$1
    require-host
    require-value stage
    if ! has-stage-output "$stage"; then
        error "Required cached output for stage $stage is missing, please re-run stage $stage."
    fi
}

# removes cached output for the given experiment stage, spares top-level output files
clean-stage-output() {
    local stage=$1
    require-host
    require-value stage
    rm-safe "$(output-directory "$stage")"
}

# removes all output for the given experiment stage
clean-stage() {
    local stage=$1
    require-host
    require-value stage
    clean-stage-output "$stage"
    rm-safe "$(output-prefix "$stage")".*
}

# runs a stage of some experiment in a Docker container
# reads the global CONFIG_FILE variable
run-stage() {
    local stage=$1
    local dockerfile=$2
    local input_directory=$3
    local command=("${@:4}")
    require-host
    require-value stage
    if [[ -z $dockerfile ]]; then
        dockerfile=util
    fi
    if [[ ! $dockerfile =~ / ]]; then
        dockerfile=scripts/$dockerfile/Dockerfile
    fi
    if [[ -z $input_directory ]]; then
        input_directory=$(input-directory)
    else
        if [[ ! $input_directory =~ / ]]; then
            input_directory=$(output-directory $input_directory)
        fi
    fi
    local flags=
    if [[ -z ${command[*]} ]]; then
        command=("./$stage.sh")
    fi
    if [[ ${command[*]} == /bin/bash ]]; then
        flags=-it
    fi
    exec > >(append "$(output-log torte)")
    exec 2> >(append "$(output-err torte)" >&2)
    if ! has-stage-log "$stage"; then
        echo "Running stage $stage"
        clean-stage "$stage"
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
             -m "$(memory-limit)G" \
            "${DOCKER_PREFIX}_$stage" \
            "${command[@]}" \
            > >(append "$(output-log "$stage")") \
            2> >(append "$(output-err "$stage")" >&2)
        copy-output-files "$stage"
        if is-file-empty "$(output-err "$stage")"; then
            rm "$(output-err "$stage")"
        fi
    else
        echo "Skipping stage $stage"
    fi
}

# skips a stage, useful to comment out a stage temporarily
skip-stage() {
    local stage=$1
    require-host
    require-value stage
    echo "Skipping stage $stage"
}

# runs a stage by dropping into an interactive shell
debug-stage() {
    local stage=$1
    local dockerfile=$2
    local input_directory=$3
    run-stage "$stage" "$dockerfile" "$input_directory" /bin/bash
}

# merges the output files of two or more stages in a new stage
run-aggregate-stage() {
    local new_stage=$1
    local arguments=("${@:2}")
    local stages=("${@:6}")
    require-host
    require-value new_stage arguments
    if ! has-stage-log "$new_stage"; then
        for stage in "${stages[@]}"; do
            require-stage-output "$stage"
        done
    fi
    run-stage "$new_stage" "" "$OUTPUT_DIRECTORY" ./aggregate.sh "${arguments[@]}"
    if [[ $AUTO_CLEAN_STAGES == y ]]; then
        for stage in "${stages[@]}"; do
            clean-stage-output "$stage"
        done
    fi
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
    if [[ ! -f "$(output-csv "${new_stage}_1")" ]]; then
        error "Required output CSV for stage ${new_stage}_1 is missing, please re-run stage ${new_stage}_1."
    fi
    common_fields=$(table-fields-except "$(output-csv "${new_stage}_1")" "$file_field")
    run-aggregate-stage "$new_stage" "$file_field" "$stage_field" "$common_fields" "cat - | rev | cut -d_ -f1 | rev" "${stages[@]}"
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
     # path to system repositories
    INPUT_DIRECTORY=${INPUT_DIRECTORY:-input}
    # path to resulting outputs, created if necessary
    OUTPUT_DIRECTORY=${OUTPUT_DIRECTORY:-output}
    # y if building Docker images should be skipped, useful for loading imported images
    SKIP_DOCKER_BUILD=${SKIP_DOCKER_BUILD:-}
     # memory limit in GiB for running Docker containers and other tools, should be at least 2 GiB
    MEMORY_LIMIT=${MEMORY_LIMIT:-$(($(sed -n '/^MemTotal:/ s/[^0-9]//gp' /proc/meminfo)/1024/1024))}
    # y if the sources of aggregate stages should be automatically cleaned
    AUTO_CLEAN_STAGES=${AUTO_CLEAN_STAGES:-}
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
    clean-stage torte
    experiment-stages
}

# stops a running experiment
stop() {
    readarray -t containers < <(docker ps | awk '$2 ~ /^eval_/ {print $1}')
    if [[ ${#containers[@]} -gt 0 ]]; then
        docker kill "${containers[@]}"
    fi
}