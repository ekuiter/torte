#!/bin/bash

# removes all output for the given experiment stage
clean(stage) {
    require-host
    rm-safe "$(output-directory "$stage")"
}

# runs a stage of some experiment in a Docker container
# reads the EXPERIMENT_FILE environment variable
run(stage=, image=util, input_directory=, command...) {
    stage=${stage:-$TRANSIENT_STAGE}
    require-host
    local readable_stage=$stage
    if [[ $stage == "$TRANSIENT_STAGE" ]]; then
        readable_stage="<transient>"
        clean "$stage"
    fi
    log "$readable_stage"
    if [[ $FORCE_RUN == y ]] || ! stage-done "$stage"; then
        input_directory=${input_directory:-$(input-directory)}
        local dockerfile
        if [[ ! -f $image ]] && [[ -f scripts/$image/Dockerfile ]]; then
            dockerfile=scripts/$image/Dockerfile
        else
            dockerfile=$image
        fi
        if [[ ! -d $input_directory ]] && [[ -d $(output-directory "$input_directory") ]]; then
            input_directory=$(output-directory "$input_directory")
        fi
        local build_flags=
        if is-array-empty command; then
            command=("$stage")
        fi
        if [[ ! $VERBOSE == y ]]; then
            build_flags=-q
        fi
        clean "$stage"
        if [[ $SKIP_DOCKER_BUILD != y ]]; then
            compile-script "$EXPERIMENT_FILE" > "$SCRIPTS_DIRECTORY/_experiment.gen.sh"
            log "" "$(echo-progress build)"
            docker build $build_flags \
                -f "$dockerfile" \
                -t "${DOCKER_PREFIX}_$stage" \
                --ulimit nofile=20000:20000 \
                "$SCRIPTS_DIRECTORY" >/dev/null
        fi
        mkdir -p "$(output-directory "$stage")"
        log "" "$(echo-progress run)"
        docker run \
            -v "$PWD/$input_directory:$DOCKER_INPUT_DIRECTORY" \
            -v "$PWD/$(output-directory "$stage"):$DOCKER_OUTPUT_DIRECTORY" \
            -e IS_DOCKER_RUNNING=y \
            --rm \
            -m "$(memory-limit)G" \
            "${DOCKER_PREFIX}_$stage" \
            ./torte.sh "${command[@]}" \
            > >(write-all "$(output-log "$stage")") \
            2> >(write-all "$(output-err "$stage")" >&2)
        rm-if-empty "$(output-log "$stage")"
        rm-if-empty "$(output-err "$stage")"
        find "$(output-directory "$stage")" -mindepth 1 -type d -empty -delete
        if [[ $stage == "$TRANSIENT_STAGE" ]]; then
            clean "$stage"
        fi
        log "" "$(echo-done)"
    else
        log "" "$(echo-skip)"
    fi
}

# skips a stage, useful to comment out a stage temporarily
skip(stage=, image=util, input_directory=, command...) {
    echo "Skipping stage $stage"
}

# merges the output files of two or more stages in a new stage
# assumes that the input directory is the root output directory, also makes some assumptions about its layout
aggregate-helper(file_fields=, stage_field=, stage_transformer=, directory_field=, stages...) {
    directory_field=${directory_field:-$stage_field}
    stage_transformer=${stage_transformer:-$(lambda-identity)}
    require-array stages
    compile-lambda stage-transformer "$stage_transformer"
    source_transformer="$(lambda value "stage-transformer \$(basename \$(dirname \$value))")"
    csv_files=()
    for stage in "${stages[@]}"; do
        csv_files+=("$(input-directory)/$stage/$DOCKER_OUTPUT_FILE_PREFIX.csv")
        while IFS= read -r -d $'\0' file; do
            cp "$file" "$(output-path "$(stage-transformer "$stage")" "${file#"$(input-directory)/$stage/"}")"
        done < <(find "$(input-directory)/$stage" -type f -print0)
    done
    aggregate-tables "$stage_field" "$source_transformer" "${csv_files[@]}" > "$(output-csv)"
    tmp=$(mktemp)
    mutate-table-field "$(output-csv)" "$file_fields" "$directory_field" "$(lambda value,context_value echo "\$context_value\$PATH_SEPARATOR\$value")" > "$tmp"
    mv "$tmp" "$(output-csv)"
}

# merges the output files of two or more stages in a new stage
aggregate(stage, file_fields=, stage_field=, stage_transformer=, directory_field=, stages...) {
    if ! stage-done "$stage"; then
        local current_stage
        for current_stage in "${stages[@]}"; do
            require-stage-done "$current_stage"
        done
    fi
    run "$stage" "" "$OUTPUT_DIRECTORY" aggregate-helper "$file_fields" "$stage_field" "$stage_transformer" "$directory_field" "${stages[@]}"
}

# runs a stage a given number of time and merges the output files in a new stage
iterate(stage, iterations, iteration_field=iteration, file_fields=, image=util, input_directory=, command...) {
    if [[ $iterations -lt 1 ]]; then
        error "At least one iteration is required for stage $stage."
    fi
    local stages=()
    local i
    for i in $(seq "$iterations"); do
        local current_stage="${stage}_$i"
        stages+=("$current_stage")
        run "$current_stage" "$image" "$input_directory" "${command[@]}"
    done
    if [[ ! -f "$(output-csv "${stage}_1")" ]]; then
        error "Required output CSV for stage ${stage}_1 is missing, please re-run stage ${stage}_1."
    fi
    aggregate "$stage" "$file_fields" "$iteration_field" "$(lambda value "echo \$value | rev | cut -d_ -f1 | rev")" "" "${stages[@]}"
}

# runs the util Docker container as a transient stage; e.g., for a small calculation to add to an existing stage
# only run if the specified file does not exist yet
run-transient-unless(file=, command...) {
    if [[ -z $file ]] || is-file-empty "$OUTPUT_DIRECTORY/$file"; then
        run "" "" "$OUTPUT_DIRECTORY" bash -c "source torte.sh true; cd \"\$(input-directory)\"; $(to-list command "; ")"
    fi
}

# joins the results of the first stage into the results of the second stage
join-into(first_stage, second_stage) {
    run-transient-unless "$second_stage/$DOCKER_OUTPUT_FILE_PREFIX.$first_stage.csv" \
        "mv $second_stage/$DOCKER_OUTPUT_FILE_PREFIX.csv $second_stage/$DOCKER_OUTPUT_FILE_PREFIX.$first_stage.csv" \
        "join-tables $first_stage/$DOCKER_OUTPUT_FILE_PREFIX.csv $second_stage/$DOCKER_OUTPUT_FILE_PREFIX.$first_stage.csv > $second_stage/$DOCKER_OUTPUT_FILE_PREFIX.csv"
}

# forces all subsequent stages to be run
force() {
    export FORCE_RUN=y
}

# do not force all subsequent stages to be run
unforce() {
    export FORCE_RUN=
}

# plots data on the command line
plot-helper(file, type, fields, arguments...) {
    to-array fields
    local indices=()
    for field in "${fields[@]}"; do
        indices+=("$(table-field-index "$file" "$field")")
    done
    cut -d, "-f$(to-list indices)" < "$file" | uplot "$type" -d, -H "${arguments[@]}"
}

# plots data on the command line
plot(stage, type, fields, arguments...) {
    local file
    if [[ ! -f $stage ]] && [[ -f $OUTPUT_DIRECTORY/$stage/$DOCKER_OUTPUT_FILE_PREFIX.csv ]]; then
        file=$OUTPUT_DIRECTORY/$stage/$DOCKER_OUTPUT_FILE_PREFIX.csv
    else
        file=$stage
    fi
    run-transient-unless "" "plot-helper \"${file#"$OUTPUT_DIRECTORY/"}\" \"$type\" \"$fields\" ${arguments[*]}"
}