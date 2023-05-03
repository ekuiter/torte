#!/bin/bash

# removes all output for the given experiment stage
clean(stages...) {
    require-array stages
    require-host
    for stage in "${stages[@]}"; do
        rm-safe "$(output-directory "$stage")"
    done
}

# runs a stage of some experiment in a Docker container
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
        if [[ ! -f $image ]] && [[ -f $DOCKER_DIRECTORY/$image/Dockerfile ]]; then
            dockerfile=$DOCKER_DIRECTORY/$image/Dockerfile
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
            log "" "$(echo-progress build)"
            docker build $build_flags \
                -f "$dockerfile" \
                -t "${DOCKER_PREFIX}_$stage" \
                --ulimit nofile=20000:20000 \
                "$(dirname "$dockerfile")" >/dev/null
        fi
        mkdir -p "$(output-directory "$stage")"
        log "" "$(echo-progress run)"
        local cmd=(docker run)
        if [[ ${command[*]} == /bin/bash ]]; then
            cmd+=(-it)
        fi
        cmd+=(-v "$PWD/$input_directory:$DOCKER_INPUT_DIRECTORY")
        cmd+=(-v "$PWD/$(output-directory "$stage"):$DOCKER_OUTPUT_DIRECTORY")
        cmd+=(-v "$(realpath "$SCRIPTS_DIRECTORY"):$DOCKER_SCRIPTS_DIRECTORY")
        cmd+=(-e IS_DOCKER_RUNNING=y)
        cmd+=(--rm)
        cmd+=(-m "$(memory-limit)G")
        cmd+=("${DOCKER_PREFIX}_$stage")
        if [[ ${command[*]} == /bin/bash ]]; then
            cmd+=("${command[*]}")
            log "${cmd[*]}"
        else
            cmd+=("$DOCKER_SCRIPTS_DIRECTORY/$DOCKER_PREFIX.sh")
            "${cmd[@]}" "${command[@]}" \
                > >(write-all "$(output-log "$stage")") \
                2> >(write-all "$(output-err "$stage")" >&2)
        fi
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
        run "" "" "$OUTPUT_DIRECTORY" bash -c "cd $DOCKER_SCRIPTS_DIRECTORY; source $DOCKER_PREFIX.sh true; cd \"\$(input-directory)\"; $(to-list command "; ")"
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
    FORCE_RUN=y
}

# do not force all subsequent stages to be run
unforce() {
    FORCE_RUN=
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

# convenience functions for defining commonly used stages
define-stage-helpers() {
    # clone the systems specified as experiment subjects
    clone-systems() {
        run --stage clone-systems
    }

    # tag old Linux revisions that are not included in its Git history
    tag-linux-revisions(option=) {
        run --stage tag-linux-revisions --command tag-linux-revisions "$option"
    }

    # extracts code names of linux revisions
    read-linux-names(option=) {
        run --stage read-linux-names
    }

    # read basic statistics for each system
    read-statistics(option=) {
        run --stage read-statistics --command read-statistics "$option"
    }

    # extracts kconfig models with the given extractor
    extract-kconfig-models-with(extractor, output_stage=kconfig) {
        run \
            --stage "$output_stage" \
            --image "$extractor" \
            --command "extract-kconfig-models-with-$extractor"
    }

    # extracts kconfig models with kconfigreader and kmax
    extract-kconfig-models(output_stage=kconfig) {
        extract-kconfig-models-with --extractor kconfigreader --output-stage kconfigreader
        extract-kconfig-models-with --extractor kmax --output-stage kmax
        aggregate \
            --stage "$output_stage" \
            --stage-field extractor \
            --file-fields binding-file,model-file \
            --stages kconfigreader kmax
    }

    # transforms model files with FeatJAR
    transform-models-with-featjar(transformer, output_extension, input_stage=kconfig, command=transform-with-featjar, timeout=0) {
        # shellcheck disable=SC2128
        run \
            --stage "$transformer" \
            --image featjar \
            --input-directory "$input_stage" \
            --command "$command" \
            --input-extension model \
            --output-extension "$output_extension" \
            --transformer "$transformer" \
            --timeout "$timeout"
    }

    # transforms model files into DIMACS with FeatJAR
    transform-models-into-dimacs-with-featjar(transformer, input_stage=kconfig, timeout=0) {
        transform-models-with-featjar \
            --command transform-into-dimacs-with-featjar \
            --output-extension dimacs \
            --input-stage "$input_stage" \
            --transformer "$transformer" \
            --timeout "$timeout"
    }

    # transforms model files into DIMACS
    transform-models-into-dimacs(input_stage=kconfig, output_stage=dimacs, timeout=0) {
        # distributive tranformation
        transform-models-into-dimacs-with-featjar --transformer model_to_dimacs_featureide --input-stage "$input_stage" --timeout "$timeout"
        transform-models-into-dimacs-with-featjar --transformer model_to_dimacs_featjar --input-stage "$input_stage" --timeout "$timeout"
        
        # intermediate formats for CNF transformation
        transform-models-with-featjar --transformer model_to_model_featureide --output-extension featureide.model --input-stage "$input_stage" --timeout "$timeout"
        transform-models-with-featjar --transformer model_to_smt_z3 --output-extension smt --input-stage "$input_stage" --timeout "$timeout"

        # Plaisted-Greenbaum CNF tranformation
        run \
            --stage model_to_dimacs_kconfigreader \
            --image kconfigreader \
            --input-directory model_to_model_featureide \
            --command transform-into-dimacs-with-kconfigreader \
            --input-extension featureide.model \
            --timeout "$timeout"
        join-into model_to_model_featureide model_to_dimacs_kconfigreader

        # Tseitin CNF tranformation
        run \
            --stage smt_to_dimacs_z3 \
            --image z3 \
            --input-directory model_to_smt_z3 \
            --command transform-into-dimacs-with-z3 \
            --timeout "$timeout"
        join-into model_to_smt_z3 smt_to_dimacs_z3

        aggregate \
            --stage "$output_stage" \
            --directory-field dimacs-transformer \
            --file-fields dimacs-file \
            --stages model_to_dimacs_featureide model_to_dimacs_featjar model_to_dimacs_kconfigreader smt_to_dimacs_z3
    }

    # visualize community structure of DIMACS files as a JPEG file
    draw-community-structure(input_stage=dimacs, timeout=0) {
        run \
            --stage community-structure \
            --image satgraf \
            --input-directory "$input_stage" \
            --command transform-with-satgraf \
            --timeout "$timeout"
    }

    # solve DIMACS files
    solve(parser, input_stage=dimacs, timeout=0, solver_specs...) {
        local stages=()
        for solver_spec in "${solver_specs[@]}"; do
            local solver stage image
            solver=$(echo "$solver_spec" | cut -d, -f1)
            stage=${solver//\//_}
            stage=solve_${stage,,}
            image=$(echo "$solver_spec" | cut -d, -f2)
            stages+=("$stage")
            run \
                --stage "$stage" \
                --image "$image" \
                --input-directory "$input_stage" \
                --command solve \
                --solver "$solver" \
                --parser "$parser" \
                --timeout "$timeout"
        done
        aggregate --stage "solve_$parser" --stages "${stages[@]}"
    }

    # solve DIMACS files for satisfiability
    solve-satisfiability(input_stage=dimacs, timeout=0) {
        local solver_specs=(
            z3,z3
            other/sat4j.sh,solver
            sat-competition/02-zchaff,solver
            sat-competition/03-Forklift,solver
            sat-competition/04-zchaff,solver
            sat-competition/05-SatELiteGTI.sh,solver
            sat-competition/06-MiniSat,solver
            sat-competition/07-RSat.sh,solver
            sat-competition/09-precosat,solver
            sat-competition/10-CryptoMiniSat,solver
            sat-competition/11-glucose.sh,solver
            sat-competition/11-SatELite,solver
            sat-competition/12-glucose.sh,solver
            sat-competition/12-SatELite,solver
            sat-competition/13-lingeling-aqw,solver
            sat-competition/14-lingeling-ayv,solver
            sat-competition/16-MapleCOMSPS_DRUP,solver
            sat-competition/17-Maple_LCM_Dist,solver
            sat-competition/18-MapleLCMDistChronoBT,solver
            sat-competition/19-MapleLCMDiscChronoBT-DL-v3,solver
            sat-competition/20-Kissat-sc2020-sat,solver
            sat-competition/21-Kissat_MAB,solver
        )
        solve --parser satisfiable --input-stage "$input_stage" --timeout "$timeout" --solver_specs "${solver_specs[@]}"
    }

    # solve DIMACS files for model count
    solve-model-count(input_stage=dimacs, timeout=0) {
        local solver_specs=(
            other/d4.sh,solver
            emse-2023/countAntom,solver
            emse-2023/d4,solver
            emse-2023/dsharp,solver
            emse-2023/ganak,solver
            emse-2023/sharpSAT,solver
        )
        solve --parser model-count --input-stage "$input_stage" --timeout "$timeout" --solver_specs "${solver_specs[@]}"
    }

    log-output-field(stage, field) {
        log "$field: $(table-field "$(output-directory "$stage")/output.csv" "$field" | sort | uniq | tr '\n' ' ')"
    }
}