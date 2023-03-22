#!/bin/bash

# removes all output for the given experiment stage
clean-stage(stage) {
    require-host
    rm-safe "$(output-directory "$stage")"
}

# runs a stage of some experiment in a Docker container
# reads the global CONFIG_FILE variable
run-stage(stage=$TRANSIENT_STAGE, dockerfile=util, input_directory=, command...) {
    require-host
    if [[ $FORCE_RUN == y ]] || ! stage-done "$stage"; then
        echo "Running stage $stage"
        input_directory=${input_directory:-$(input-directory)}
        if [[ ! -f $dockerfile ]] && [[ -f scripts/$dockerfile/Dockerfile ]]; then
            dockerfile=scripts/$dockerfile/Dockerfile
        fi
        if [[ ! -d $input_directory ]] && [[ -d $(output-directory "$input_directory") ]]; then
            input_directory=$(output-directory "$input_directory")
        fi
        local flags=
        if is-array-empty command; then
            command=("./$stage.sh")
        fi
        if [[ ${command[*]} == /bin/bash ]]; then
            flags=-it
        fi
        mkdir -p "$(output-directory "$DOCKER_PREFIX")"
        exec > >(tee -a "$(output-log "$DOCKER_PREFIX")")
        exec 2> >(tee -a "$(output-err "$DOCKER_PREFIX")" >&2)
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
            > >(tee -a "$(output-log "$stage")") \
            2> >(tee -a "$(output-err "$stage")" >&2)
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
skip-stage(stage=$TRANSIENT_STAGE, dockerfile=util, input_directory=, command...) {
    echo "Skipping stage $stage"
}

# runs a stage by dropping into an interactive shell
debug-stage(stage=$TRANSIENT_STAGE, dockerfile=util, input_directory=) {
    run-stage "$stage" "$dockerfile" "$input_directory" /bin/bash
}

# merges the output files of two or more stages in a new stage
run-aggregate-stage(stage, stage_field, file_fields=, stage_transformer=, stages...) {
    if ! stage-done "$stage"; then
        local current_stage
        for current_stage in "${stages[@]}"; do
            require-stage-done "$current_stage"
        done
    fi
    run-stage "$stage" "" "$OUTPUT_DIRECTORY" ./aggregate.sh "$stage_field" "$file_fields" "$stage_transformer" "${stages[@]}"
}

# runs a stage a given number of time and merges the output files in a new stage
run-iterated-stage(stage, iterations, iteration_field=iteration, file_fields=, dockerfile=util, input_directory=, command...) {
    if [[ $iterations -lt 1 ]]; then
        error "At least one iteration is required for stage $stage."
    fi
    local stages=()
    local i
    for i in $(seq "$iterations"); do
        local current_stage="${stage}_$i"
        stages+=("$current_stage")
        run-stage "$current_stage" "$dockerfile" "$input_directory" "${command[@]}"
    done
    if [[ ! -f "$(output-csv "${stage}_1")" ]]; then
        error "Required output CSV for stage ${stage}_1 is missing, please re-run stage ${stage}_1."
    fi
    run-aggregate-stage "$stage" "$iteration_field" "$file_fields" "$(lambda value "echo \$value | rev | cut -d_ -f1 | rev")" "${stages[@]}"
}

# runs the util Docker container as a transient stage; e.g., for a small calculation to add to an existing stage
# only run if the specified file does not exist yet
run-util-unless(file, command...) {
    if is-file-empty "$OUTPUT_DIRECTORY/$file"; then
        run-stage "" "" "$OUTPUT_DIRECTORY" bash -c "source torte.sh load-config; cd \"\$(input-directory)\"; $(to-list command "; ")"
    fi
}

run-join-into(first_stage, second_stage) {
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
load-subjects(config_file=) {
    load-config "$config_file"
    experiment-subjects
}

# removes all output files specified by the given config file
# does not touch input files or Docker images
clean(config_file=) {
    require-host
    load-config "$config_file"
    rm-safe "$OUTPUT_DIRECTORY"
}

# runs the experiment defined in the given config file
run(config_file=) {
    require-host
    require-command docker
    load-config "$config_file"
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
