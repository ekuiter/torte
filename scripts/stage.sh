#!/bin/bash

# removes all output for the given experiment stage
clean(stage) {
    require-host
    rm-safe "$(output-directory "$stage")"
}

# runs a stage of some experiment in a Docker container
# reads the EXPERIMENT_FILE environment variable
run(stage=$TRANSIENT_STAGE, dockerfile=util, input_directory=, command...) {
    require-host
    log "$stage"
    if [[ $FORCE_RUN == y ]] || ! stage-done "$stage"; then
        input_directory=${input_directory:-$(input-directory)}
        if [[ ! -f $dockerfile ]] && [[ -f scripts/$dockerfile/Dockerfile ]]; then
            dockerfile=scripts/$dockerfile/Dockerfile
        fi
        if [[ ! -d $input_directory ]] && [[ -d $(output-directory "$input_directory") ]]; then
            input_directory=$(output-directory "$input_directory")
        fi
        local build_flags=
        local run_flags=
        if is-array-empty command; then
            command=("$stage.sh")
        fi
        if [[ ! $VERBOSE == y ]]; then
            build_flags=-q
        fi
        if [[ ${command[*]} == /bin/bash ]]; then
            run_flags=-it
        fi
        clean "$stage"
        if [[ $SKIP_DOCKER_BUILD != y ]]; then
            cp "$EXPERIMENT_FILE" "$SCRIPTS_DIRECTORY/_experiment.sh"
            log "$stage" "$(echo-progress build)"
            docker build $build_flags \
                -f "$dockerfile"\
                -t "${DOCKER_PREFIX}_$stage" \
                --ulimit nofile=20000:20000 \
                "$SCRIPTS_DIRECTORY" >/dev/null
        fi
        mkdir -p "$(output-directory "$stage")"
        log "$stage" "$(echo-progress run)"
        docker run $run_flags \
            -v "$PWD/$input_directory:$DOCKER_INPUT_DIRECTORY" \
            -v "$PWD/$(output-directory "$stage"):$DOCKER_OUTPUT_DIRECTORY" \
            -e DOCKER_RUNNING=y \
            --rm \
            -m "$(memory-limit)G" \
            "${DOCKER_PREFIX}_$stage" \
            ./torte.sh "${command[@]}" \
            > >(write-all "$(output-log "$stage")") \
            2> >(write-all "$(output-err "$stage")" >&2)
        rm-if-empty "$(output-log "$stage")"
        rm-if-empty "$(output-err "$stage")"
        if [[ $stage == "$TRANSIENT_STAGE" ]]; then
            clean "$stage"
        fi
        log "$stage" "$(echo-done)"
    else
        log "$stage" "$(echo-skip)"
    fi
}

# skips a stage, useful to comment out a stage temporarily
skip(stage=$TRANSIENT_STAGE, dockerfile=util, input_directory=, command...) {
    echo "Skipping stage $stage"
}

# runs a stage by dropping into an interactive shell
debug(stage=$TRANSIENT_STAGE, dockerfile=util, input_directory=) {
    run "$stage" "$dockerfile" "$input_directory" /bin/bash
}

# merges the output files of two or more stages in a new stage
aggregate(stage, stage_field, file_fields=, stage_transformer=, stages...) {
    if ! stage-done "$stage"; then
        local current_stage
        for current_stage in "${stages[@]}"; do
            require-stage-done "$current_stage"
        done
    fi
    run "$stage" "" "$OUTPUT_DIRECTORY" aggregate.sh "$stage_field" "$file_fields" "$stage_transformer" "${stages[@]}"
}

# runs a stage a given number of time and merges the output files in a new stage
iterate(stage, iterations, iteration_field=iteration, file_fields=, dockerfile=util, input_directory=, command...) {
    if [[ $iterations -lt 1 ]]; then
        error "At least one iteration is required for stage $stage."
    fi
    local stages=()
    local i
    for i in $(seq "$iterations"); do
        local current_stage="${stage}_$i"
        stages+=("$current_stage")
        run "$current_stage" "$dockerfile" "$input_directory" "${command[@]}"
    done
    if [[ ! -f "$(output-csv "${stage}_1")" ]]; then
        error "Required output CSV for stage ${stage}_1 is missing, please re-run stage ${stage}_1."
    fi
    aggregate "$stage" "$iteration_field" "$file_fields" "$(lambda value "echo \$value | rev | cut -d_ -f1 | rev")" "${stages[@]}"
}

# runs the util Docker container as a transient stage; e.g., for a small calculation to add to an existing stage
# only run if the specified file does not exist yet
run-transient-unless(file, command...) {
    if is-file-empty "$OUTPUT_DIRECTORY/$file"; then
        run "" "" "$OUTPUT_DIRECTORY" bash -c "cd \"\$(input-directory)\"; $(to-list command "; ")"
    fi
}

join-into(first_stage, second_stage) {
    run-transient-unless "$second_stage/output.csv.old" \
        "mv $second_stage/output.csv $second_stage/output.csv.old" \
        "join-tables $first_stage/output.csv $second_stage/output.csv.old > $second_stage/output.csv"
}

# forces all subsequent stages to be run (again)
force() {
    export FORCE_RUN=y
}

unforce() {
    export FORCE_RUN=
}
