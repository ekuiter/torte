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
run(image=util, input=, output=, resumable=, command...) {
    output=${output:-$TRANSIENT_STAGE}
    assert-host
    local readable_stage=$output
    if [[ $output == "$TRANSIENT_STAGE" ]]; then
        readable_stage="<transient>"
        clean "$output"
    fi
    log "$readable_stage"

    # run stage if not done or forced
    if [[ $FORCE_RUN == y ]] || ! stage-done "$output"; then
        # to prepare the Docker image, identify the correct dockerfile
        local dockerfile=$DOCKER_DIRECTORY/$image/Dockerfile
        if [[ ! -f $dockerfile ]]; then
            error "Could not find Dockerfile for image $image."
        fi

        # build and run on the platform specified in the dockerfile
        # this is useful to execute binaries built for a different architecture than the host
        local platform
        if grep -q platform-override= "$dockerfile"; then
            platform=$(grep platform-override= "$dockerfile" | cut -d= -f2)
        fi

        # by default, completely rerun the stage if it was not fully completed before
        # certain stages are able to continue from where they left off, so allow that if requested
        if [[ -z $resumable ]]; then
            clean "$output"
        fi

        if [[ -f $image.tar.gz ]]; then
            # load prebuilt Docker image if available
            if ! docker image inspect "${TOOL}_$image" > /dev/null 2>&1; then
                log "" "$(echo-progress load)"
                docker load -i "$image.tar.gz"
            fi
        else
            # (re-)build Docker image
            log "" "$(echo-progress build)"
            local cmd=(docker build)
            if [[ -z $VERBOSE ]]; then
                cmd+=(-q)
            fi
            if [[ -n $FORCE_BUILD ]]; then
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
            # to run the stage's Docker container, first prepare the stage directory
            log "" "$(echo-progress run)"
            mkdir -p "$(stage-directory "$output")"
            chmod 0777 "$(stage-directory "$output")"

            # prepare shared context used for passing data between stages for caching purposes
            # first, move any existing shared directory from an unfinished stage to the global shared directory
            shared_directories=("$(stages-directory)"/*/"$SHARED_DIRECTORY")
            [ -e "${shared_directories[0]}" ] && mv "${shared_directories[@]}" "$(stages-directory)/$SHARED_DIRECTORY" || true
            # if there was no unfinished stage, either the shared directory was already prepared by the last stage,
            # or it does not exist yet, so create it
            mkdir -p "$(stages-directory)/$SHARED_DIRECTORY"
            # preparation done, make shared context available to this stage
            mv "$(stages-directory)/$SHARED_DIRECTORY" "$(stage-directory "$output")/$SHARED_DIRECTORY"

            # prepare "docker run" command
            local cmd=(docker run)
            if is-array-empty command; then
                command=("$output") # for convenience, we can omit the command to run if it is the same as the stage name
            fi
            if [[ $DEBUG == y ]]; then
                command=(/bin/bash) # run shell if in debug mode
            fi

            # mount input directories
            if [[ $output != "$ROOT_STAGE" ]]; then
                # for convenience, mount root stage by default, as we use it often
                input=${input:-$MAIN_INPUT_KEY=$ROOT_STAGE}
            fi
            # if only one input is given, it is mounted as the main input
            if [[ -n $input ]] && [[ $input != *=* ]]; then
                assert-stage-done "$input"
                input="$MAIN_INPUT_KEY=$input"
            fi
            input_directories=$(echo "$input" | tr "," "\n")
            # if several inputs are given, mount them under their respective keys
            for input_directory_pair in $input_directories; do
                local key=${input_directory_pair%%=*}
                local input_directory=${input_directory_pair##*=}
                if [[ -z $key ]] || [[ -z $input_directory ]]; then
                    continue
                fi
                assert-stage-done "$input_directory"
                input_directory=$(stage-directory "$input_directory")
                local input_volume=$input_directory
                if [[ $input_volume != /* ]]; then
                    input_volume=$PWD/$input_volume
                fi
                cmd+=(-v "$input_volume:$DOCKER_INPUT_DIRECTORY/$key")
            done

            # mount output directory
            local output_volume
            output_volume=$(stage-directory "$output")
            if [[ $output_volume != /* ]]; then
                output_volume=$PWD/$output_volume
            fi
            cmd+=(-v "$output_volume:$DOCKER_OUTPUT_DIRECTORY")

            cmd+=(-v "$(realpath "$SRC_DIRECTORY"):$DOCKER_SRC_DIRECTORY") # mount source code of the tool
            cmd+=(-e INSIDE_STAGE="$output") # tell the stage about itself
            cmd+=(-e PROFILE) # tell the stage if profiling is enabled ...
            cmd+=(-e TEST) # ... if testing is enabled ...
            cmd+=(-e CI) # ... and if running in CI environment
            cmd+=(-e PASS) # also tell it about which pass of a multi-pass experiment is supposed to be run
            cmd+=(--init) # proper signal and exit handling
            if [[ ${command[*]} == /bin/bash ]] && [[ -z "$CI" ]]; then
                cmd+=(-it) # needed for debugging in a terminal
            fi
            cmd+=(--rm) # run as one-off container, which is removed afterwards
            cmd+=(-m "$(memory-limit)G") # set memory limit
            if [[ -n $platform ]]; then
                cmd+=(--platform "$platform") # set platform to match build platform
            fi
            cmd+=(--entrypoint /bin/bash) # whatever command is given, run it through bash
            cmd+=("${TOOL}_$image") # specify Docker image to run

            # run the command inside the Docker container
            if [[ ${command[*]} == /bin/bash ]]; then
                # in debug mode, drop into an interactive shell and exit afterwards
                log "" "${cmd[*]}"
                "${cmd[@]}"
                exit
            else
                # in production, run the given command in the context of the tool, and log errors and output
                cmd+=("$DOCKER_SRC_DIRECTORY/main.sh")
                "${cmd[@]}" "${command[@]}" \
                    > >(write-all "$(stage-log "$output")") \
                    2> >(write-all "$(stage-err "$output")" >&2)
                FORCE_NEW_LOG=y # flush log buffer after stage is done
            fi

            # move shared context back so the next stage can use it
            mv "$(stage-directory "$output")/$SHARED_DIRECTORY" "$(stages-directory)/$SHARED_DIRECTORY"

            # clean up empty log files and transient stages
            rm-if-empty "$(stage-log "$output")"
            rm-if-empty "$(stage-err "$output")"
            if [[ $output == "$TRANSIENT_STAGE" ]]; then
                clean "$output"
            fi
        else
            # in export mode, save the Docker image for later use
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
        # mark stage as completed, so it won't be rerun unless forced or cleaned
        if [[ $output != "$TRANSIENT_STAGE" ]]; then
            touch "$(stage-done-file "$output")"
        fi
        log "" "$(echo-done)"
    else
        log "" "$(echo-skip)"
    fi
}

# skips a stage, useful to comment out a stage temporarily
skip(image=util, input=, output=, resumable=, command...) {
    echo "Skipping stage $output"
}

# merges the output files of two or more input stages in a new stage
# assumes that the input directory is the root output directory, also makes some assumptions about its layout
aggregate-helper(file_fields=, stage_field=, stage_transformer=, directory_field=, inputs...) {
    directory_field=${directory_field:-$stage_field}
    stage_transformer=${stage_transformer:-$(lambda-identity)}
    assert-array inputs
    source-lambda "$stage_transformer"
    source_transformer="$(lambda value "\"\$stage_transformer\" \$(basename \$(dirname \$value))")"
    csv_files=()
    for stage in "${inputs[@]}"; do
        csv_files+=("$(input-directory "$stage")/$OUTPUT_FILE_PREFIX.csv")
    done
    aggregate-tables "$stage_field" "$source_transformer" "${csv_files[@]}" > "$(output-csv)"
    for stage in "${inputs[@]}"; do
        while IFS= read -r -d $'\0' file; do
            mv "$file" "$(output-path "$("$stage_transformer" "$stage")" "${file#"$(input-directory "$stage")/"}")"
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
    run \
        --image util \
        --input "$input" \
        --output "$output" \
        --command aggregate-helper \
            --file-fields "$file_fields" \
            --stage-field "$stage_field" \
            --stage-transformer "$stage_transformer" \
            --directory-field "$directory_field" \
            --inputs "${inputs[@]}"
    for current_stage in "${inputs[@]}"; do
        echo "$output" > "$(stage-moved-file "$current_stage")"
    done
}

# runs a stage a given number of time and merges the output files in a new stage
iterate(iterations, iteration_field=iteration, file_fields=, image=util, input=, output=, resumable=, command...) {
    if [[ $iterations -lt 1 ]]; then
        error "At least one iteration is required for stage $output."
    fi
    if [[ $iterations -eq 1 ]]; then
        run \
            --image "$image" \
            --input "$input" \
            --output "$output" \
            --resumable "$resumable" \
            --command "${command[@]}"
    else
        local stages=()
        local i
        for i in $(seq "$iterations"); do
            local current_stage="${output}-$i"
            stages+=("$current_stage")
            run \
                --image "$image" \
                --input "$input" \
                --output "$current_stage" \
                --resumable "$resumable" \
                --command "${command[@]}"
        done
        if [[ ! -f "$(stage-csv "${output}-1")" ]]; then
            error "Required output CSV for stage ${output}-1 is missing, please re-run stage ${output}-1."
        fi
        aggregate "$output" "$file_fields" "$iteration_field" "$(lambda value "echo \$value | rev | cut -d- -f1 | rev")" "" "${stages[@]}"
    fi
}

# runs the util Docker container as a transient stage; e.g., for a small calculation to add to an existing stage
# only run if the specified file does not exist yet or is empty
# should be run before the existing stage is moved (e.g., by an aggregation)
run-transient-unless(file=, input=, command...) {
    local file_path
    file_path="$(stages-directory)/$file"
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
        run \
            --image util \
            --input "$input" \
            --output "" \
            --command bash -c "cd $DOCKER_SRC_DIRECTORY; source main.sh true; $(to-list command "; ")"
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