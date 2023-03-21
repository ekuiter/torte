#!/bin/bash

# removes all output for the given experiment stage
clean-stage() {
    local stage=$1
    require-host
    require-value stage
    rm-safe "$(output-directory "$stage")"
}

# runs a stage of some experiment in a Docker container
# reads the global CONFIG_FILE variable
run-stage() {
    local stage=${1:-$TRANSIENT_STAGE}
    local dockerfile=${2:-util}
    local input_directory=${3:-$(input-directory)}
    local command=("${@:4}")
    require-host
    if [[ ! -f $dockerfile ]] && [[ -f scripts/$dockerfile/Dockerfile ]]; then
        dockerfile=scripts/$dockerfile/Dockerfile
    fi
    if [[ ! -d $input_directory ]] && [[ -d $(output-directory "$input_directory") ]]; then
        input_directory=$(output-directory "$input_directory")
    fi
    local flags=
    if [[ -z ${command[*]} ]]; then
        command=("./$stage.sh")
    fi
    if [[ ${command[*]} == /bin/bash ]]; then
        flags=-it
    fi
    mkdir -p "$(output-directory "$DOCKER_PREFIX")"
    exec > >(append "$(output-log "$DOCKER_PREFIX")")
    exec 2> >(append "$(output-err "$DOCKER_PREFIX")" >&2)
    if [[ $FORCE_RUN == y ]] || ! stage-done "$stage"; then
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
        rm-if-empty "$(output-log "$stage")"
        rm-if-empty "$(output-err "$stage")"
        if [[ $stage == "$TRANSIENT_STAGE" ]]; then
            clean-stage "$stage"
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
    local stages=("${@:5}")
    require-host
    require-value new_stage arguments
    if ! stage-done "$new_stage"; then
        for stage in "${stages[@]}"; do
            require-stage-done "$stage"
        done
    fi
    run-stage "$new_stage" "" "$OUTPUT_DIRECTORY" ./aggregate.sh "${arguments[@]}"
}

# runs a stage a given number of time and merges the output files in a new stage
run-iterated-stage() {
    local iteration_field=$1
    local iterations=$2
    local file_fields=$3
    local new_stage=$4
    local arguments=("${@:5}")
    require-host
    require-value iteration_field iterations new_stage arguments
    local stages=()
    for i in $(seq "$iterations"); do
        local stage="${new_stage}_$i"
        stages+=("$stage")
        run-stage "$stage" "${arguments[@]}"
    done
    if [[ ! -f "$(output-csv "${new_stage}_1")" ]]; then
        error "Required output CSV for stage ${new_stage}_1 is missing, please re-run stage ${new_stage}_1."
    fi
    run-aggregate-stage "$new_stage" "$iteration_field" "$(lambda value "echo \$value | rev | cut -d_ -f1 | rev")" "$file_fields" "${stages[@]}"
}

# runs the util Docker container as a transient stage; e.g., for a small calculation to add to an existing stage
# only run if the specified file does not exist yet
run-util-unless() {
    local file=$1
    local command=("${@:2}")
    require-value file command
    if is-file-empty "$OUTPUT_DIRECTORY/$file"; then
        run-stage \
        `# stage` "" \
        `# dockerfile` "" \
        `# input directory` "$OUTPUT_DIRECTORY" \
        `# command` bash -c "source torte.sh load-config; cd \"\$(input-directory)\"; $(IFS=';'; echo "${command[*]}")"
    fi
}

run-join-into() {
    local first_stage=$1
    local second_stage=$2
    require-value first_stage second_stage
    run-util-unless "$second_stage/output.csv.old" \
        "mv $second_stage/output.csv $second_stage/output.csv.old" \
        "join-tables $first_stage/output.csv $second_stage/output.csv.old > $second_stage/output.csv"
}

# forces all subsequent stages to be run (again)
force-run-below() {
    export FORCE_RUN=y
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
    # y if every following stage should be forced to run regardless of whether is is already done
    FORCE_RUN=${FORCE_RUN:-}
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
    clean-stage "$DOCKER_PREFIX"
    experiment-stages
}

# stops a running experiment
stop() {
    readarray -t containers < <(docker ps | awk '$2 ~ /^eval_/ {print $1}')
    if [[ ${#containers[@]} -gt 0 ]]; then
        docker kill "${containers[@]}"
    fi
}