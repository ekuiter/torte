#!/bin/bash
# runs stages


TRANSIENT_STAGE=transient # name for transient stages
SHARED_DIRECTORY=.shared # path for data shared by all stages (use with care, as stages are intentionally separated)

# removes all output for the given experiment stage
clean(stages...) {
    assert-array stages
    assert-host
    for stage in "${stages[@]}"; do
        rm-safe "$(stage-directory "$stage")"
    done
}

# runs a stage of some experiment in a Docker container
run(image=util, input=, output=, command...) {
    output=${output:-$TRANSIENT_STAGE}
    assert-host
    local readable_stage=$output
    if [[ $output == "$TRANSIENT_STAGE" ]]; then
        readable_stage="<transient>"
        clean "$output"
    fi
    log "$readable_stage"
    if [[ $FORCE_RUN == y ]] || ! stage-done "$output"; then
        local dockerfile=$DOCKER_DIRECTORY/$image/Dockerfile
        if [[ ! -f $dockerfile ]]; then
            error "Could not find Dockerfile for image $image."
        fi
        local build_flags=
        if is-array-empty command; then
            command=("$output")
        fi
        local platform
        if grep -q platform-override= "$dockerfile"; then
            platform=$(grep platform-override= "$dockerfile" | cut -d= -f2)
        fi
        clean "$output"
        if [[ -f $image.tar.gz ]]; then
            if ! docker image inspect "${TOOL}_$image" > /dev/null 2>&1; then
                log "" "$(echo-progress load)"
                docker load -i "$image.tar.gz"
            fi
        else
            log "" "$(echo-progress build)"
            local cmd=(docker build)
            if [[ ! $VERBOSE == y ]]; then
                cmd+=(-q)
            fi
            if [[ $FORCE_BUILD == y ]]; then
                cmd+=(--no-cache)
            fi
            cmd+=(-f "$dockerfile")
            cmd+=(-t "${TOOL}_$image")
            cmd+=(--ulimit nofile=20000:20000)
            if [[ -n $platform ]]; then
                cmd+=(--platform "$platform")
            fi
            cmd+=("$(dirname "$dockerfile")")
            "${cmd[@]}" >/dev/null
        fi
        if [[ -z $DOCKER_EXPORT ]]; then
            mkdir -p "$(stage-directory "$output")"
            chmod 0777 "$(stage-directory "$output")"
            log "" "$(echo-progress run)"
            mkdir -p "$(stages-directory)/$SHARED_DIRECTORY"
            mv "$(stages-directory)/$SHARED_DIRECTORY" "$(stage-directory "$output")/$SHARED_DIRECTORY"
            local cmd=(docker run)
            if [[ $DEBUG == y ]]; then
                command=(/bin/bash)
            fi
            if [[ ${command[*]} == /bin/bash ]]; then
                cmd+=(-it)
            fi

            if [[ $output != "$ROOT_STAGE" ]]; then
                input=${input:-$MAIN_INPUT_KEY=$ROOT_STAGE}
            fi
            if [[ -n $input ]] && [[ $input != *=* ]]; then
                assert-stage-done "$input"
                input="$MAIN_INPUT_KEY=$input"
            fi
            input_directories=$(echo "$input" | tr "," "\n")
            for input_directory_pair in $input_directories; do
                local key=${input_directory_pair%%=*}
                local input_directory=${input_directory_pair##*=}
                assert-stage-done "$input_directory"
                input_directory=$(stage-directory "$input_directory")
                local input_volume=$input_directory
                if [[ $input_volume != /* ]]; then
                    input_volume=$PWD/$input_volume
                fi
                cmd+=(-v "$input_volume:$DOCKER_INPUT_DIRECTORY/$key")
            done
            local output_volume
            output_volume=$(stage-directory "$output")
            if [[ $output_volume != /* ]]; then
                output_volume=$PWD/$output_volume
            fi
            cmd+=(-v "$output_volume:$DOCKER_OUTPUT_DIRECTORY")
            cmd+=(-v "$(realpath "$SRC_DIRECTORY"):$DOCKER_SRC_DIRECTORY")

            cmd+=(-e INSIDE_STAGE="$output")
            cmd+=(-e PROFILE)
            cmd+=(-e TEST)
            cmd+=(-e CI)
            cmd+=(-e PASS)
            cmd+=(--rm)
            cmd+=(-m "$(memory-limit)G")
            if [[ -n $platform ]]; then
                cmd+=(--platform "$platform")
            fi
            cmd+=(--entrypoint /bin/bash)
            cmd+=("${TOOL}_$image")
            if [[ ${command[*]} == /bin/bash ]]; then
                log "" "${cmd[*]}"
                "${cmd[@]}"
                exit
            else
                cmd+=("$DOCKER_SRC_DIRECTORY/main.sh")
                "${cmd[@]}" "${command[@]}" \
                    > >(write-all "$(stage-log "$output")") \
                    2> >(write-all "$(stage-err "$output")" >&2)
                FORCE_NEW_LOG=y
            fi
            mv "$(stage-directory "$output")/$SHARED_DIRECTORY" "$(stages-directory)/$SHARED_DIRECTORY"
            rm-if-empty "$(stage-log "$output")"
            rm-if-empty "$(stage-err "$output")"
            if [[ $output == "$TRANSIENT_STAGE" ]]; then
                clean "$output"
            fi
        else
            assert-command gzip
            local image_archive
            image_archive="$EXPORT_DIRECTORY/$image.tar.gz"
            mkdir -p "$(dirname "$image_archive")"
            mkdir -p "$(stage-directory "$stage")"
            if [[ ! -f $image_archive ]]; then
                log "" "$(echo-progress save)"
                docker save "${TOOL}_$image" | gzip > "$image_archive"
            fi
        fi
        touch "$(stage-done-file "$output")"
        log "" "$(echo-done)"
    else
        log "" "$(echo-skip)"
    fi
}

# skips a stage, useful to comment out a stage temporarily
skip(image=util, input=, output=, command...) {
    echo "Skipping stage $output"
}

# merges the output files of two or more input stages in a new stage
# assumes that the input directory is the root output directory, also makes some assumptions about its layout
aggregate-helper(file_fields=, stage_field=, stage_transformer=, directory_field=, inputs...) {
    directory_field=${directory_field:-$stage_field}
    stage_transformer=${stage_transformer:-$(lambda-identity)}
    assert-array inputs
    compile-lambda stage-transformer "$stage_transformer"
    source_transformer="$(lambda value "stage-transformer \$(basename \$(dirname \$value))")"
    csv_files=()
    for stage in "${inputs[@]}"; do
        csv_files+=("$(input-directory "$stage")/$OUTPUT_FILE_PREFIX.csv")
    done
    aggregate-tables "$stage_field" "$source_transformer" "${csv_files[@]}" > "$(output-csv)"
    for stage in "${inputs[@]}"; do
        while IFS= read -r -d $'\0' file; do
            mv "$file" "$(output-path "$(stage-transformer "$stage")" "${file#"$(input-directory "$stage")/"}")"
        done < <(find "$(input-directory "$stage")" -type f -print0)
        find "$(input-directory "$stage")" -type d -empty -delete 2>/dev/null || true
    done
    tmp=$(mktemp)
    mutate-table-field "$(output-csv)" "$file_fields" "$directory_field" "$(lambda value,context_value echo "\$context_value\$PATH_SEPARATOR\$value")" > "$tmp"
    cp "$tmp" "$(output-csv)"
    rm-safe "$tmp"
}

# merges the output files of two or more input stages in a new stage
aggregate(output, file_fields=, stage_field=, stage_transformer=, directory_field=, inputs...) {
    local current_stage input
    if ! stage-done "$output"; then
        for current_stage in "${inputs[@]}"; do
            assert-stage-done "$current_stage"
        done
    fi
    for current_stage in "${inputs[@]}"; do
        input=$input,$current_stage=$current_stage
    done
    input=${input#,}
    run util "$input" "$output" aggregate-helper "$file_fields" "$stage_field" "$stage_transformer" "$directory_field" "${inputs[@]}"
    for current_stage in "${inputs[@]}"; do
        echo "$output" > "$(stage-moved-file "$current_stage")"
    done
}

# runs a stage a given number of time and merges the output files in a new stage
iterate(iterations, iteration_field=iteration, file_fields=, image=util, input=, output=, command...) {
    if [[ $iterations -lt 1 ]]; then
        error "At least one iteration is required for stage $output."
    fi
    if [[ $iterations -eq 1 ]]; then
        run "$image" "$input" "$output" "${command[@]}"
    else
        local stages=()
        local i
        for i in $(seq "$iterations"); do
            local current_stage="${output}-$i"
            stages+=("$current_stage")
            run "$image" "$input" "$current_stage" "${command[@]}"
        done
        if [[ ! -f "$(stage-csv "${output}-1")" ]]; then
            error "Required output CSV for stage ${output}-1 is missing, please re-run stage ${output}-1."
        fi
        aggregate "$output" "$file_fields" "$iteration_field" "$(lambda value "echo \$value | rev | cut -d_ -f1 | rev")" "" "${stages[@]}"
    fi
}

# runs the util Docker container as a transient stage; e.g., for a small calculation to add to an existing stage
# only run if the specified file does not exist yet
# should be run before the existing stage is moved (e.g., by an aggregation)
run-transient-unless(file=, input=, command...) {
    local file_path="$(stages-directory)/$file"
    if [[ "$file" == */* ]]; then
        local stage_part="${file%%/*}"
        local file_part="${file#*/}"
        local stage_dir
        stage_dir=$(stage-directory "$stage_part")
        file_path="$stage_dir/$file_part"
        if stage-moved "$stage_part"; then
            return
        fi
    fi
    if ([[ -z $file ]] || is-file-empty "$file_path") && [[ -z $DOCKER_EXPORT ]]; then
        run util "$input" "" bash -c "cd $DOCKER_SRC_DIRECTORY; source main.sh true; $(to-list command "; ")"
    fi
}

# joins the results of the first stage into the results of the second stage
join-into(first_stage, second_stage) {
    run-transient-unless "$second_stage/$OUTPUT_FILE_PREFIX.$first_stage.csv" \
        "1=$first_stage,2=$second_stage" \
        "mv $DOCKER_INPUT_DIRECTORY/2/$OUTPUT_FILE_PREFIX.csv $DOCKER_INPUT_DIRECTORY/2/$OUTPUT_FILE_PREFIX.$first_stage.csv" \
        "join-tables $DOCKER_INPUT_DIRECTORY/1/$OUTPUT_FILE_PREFIX.csv $DOCKER_INPUT_DIRECTORY/2/$OUTPUT_FILE_PREFIX.$first_stage.csv > $DOCKER_INPUT_DIRECTORY/2/$OUTPUT_FILE_PREFIX.csv"
}

# forces all subsequent stages to be run
force-run() {
    FORCE_RUN=y
}

# forces all subsequently run Docker images to be built without cache
force-build() {
    FORCE_BUILD=y
}

# debugs the next stage interactively
debug() {
    DEBUG=y
}

# increases verbosity
verbose() {
    VERBOSE=y
    set -x
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
    if [[ ! -f $stage ]] && [[ -f $(stage-csv "$stage") ]]; then
        file=$(stage-csv "$stage")
    else
        file=$stage
    fi
    run-transient-unless "" "plot-helper \"${file#"$(stages-directory)/"}\" \"$type\" \"$fields\" ${arguments[*]}"
}