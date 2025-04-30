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
        local platform
        if grep -q platform-override= "$dockerfile"; then
            platform=$(grep platform-override= "$dockerfile" | cut -d= -f2)
        fi
        clean "$stage"
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
            cmd+=(-f "$dockerfile")
            cmd+=(-t "${TOOL}_$image")
            cmd+=(--ulimit nofile=20000:20000)
            if [[ -n $platform ]]; then
                cmd+=(--platform "$platform")
            fi
            cmd+=("$(dirname "$dockerfile")")
            "${cmd[@]}" >/dev/null
        fi
        if [[ $DOCKER_RUN == y ]]; then
            mkdir -p "$(output-directory "$stage")"
            chmod 0777 "$(output-directory "$stage")"
            log "" "$(echo-progress run)"
            mkdir -p "$OUTPUT_DIRECTORY/$CACHE_DIRECTORY"
            mv "$OUTPUT_DIRECTORY/$CACHE_DIRECTORY" "$(output-directory "$stage")/$CACHE_DIRECTORY"
            local cmd=(docker run)
            if [[ $DEBUG == y ]]; then
                command=(/bin/bash)
            fi
            if [[ ${command[*]} == /bin/bash ]]; then
                cmd+=(-it)
            fi
            local input_volume=$input_directory
            local output_volume
            output_volume=$(output-directory "$stage")
            if [[ $input_volume != /* ]]; then
                input_volume=$PWD/$input_volume
            fi
            if [[ $output_volume != /* ]]; then
                output_volume=$PWD/$output_volume
            fi
            cmd+=(-v "$input_volume:$DOCKER_INPUT_DIRECTORY")
            cmd+=(-v "$output_volume:$DOCKER_OUTPUT_DIRECTORY")
            cmd+=(-v "$(realpath "$SCRIPTS_DIRECTORY"):$DOCKER_SCRIPTS_DIRECTORY")
            cmd+=(-e IS_DOCKER_RUNNING=y)
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
                cmd+=("$DOCKER_SCRIPTS_DIRECTORY/$TOOL.sh")
                "${cmd[@]}" "${command[@]}" \
                    > >(write-all "$(output-log "$stage")") \
                    2> >(write-all "$(output-err "$stage")" >&2)
            fi
            mv "$(output-directory "$stage")/$CACHE_DIRECTORY" "$OUTPUT_DIRECTORY/$CACHE_DIRECTORY"
            rm-if-empty "$(output-log "$stage")"
            rm-if-empty "$(output-err "$stage")"
            find "$(output-directory "$stage")" -mindepth 1 -type d -empty -delete
            if [[ $stage == "$TRANSIENT_STAGE" ]]; then
                clean "$stage"
            fi
        else
            require-command gzip
            local image_archive
            image_archive="$EXPORT_DIRECTORY/$image.tar.gz"
            mkdir -p "$(dirname "$image_archive")"
            mkdir -p "$(output-directory "$stage")"
            if [[ ! -f $image_archive ]]; then
                log "" "$(echo-progress save)"
                docker save "${TOOL}_$image" | gzip > "$image_archive"
            fi
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
    cp "$tmp" "$(output-csv)"
    rm-safe "$tmp"
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
    if [[ $iterations -eq 1 ]]; then
        run "$stage" "$image" "$input_directory" "${command[@]}"
    else
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
    fi
}

# runs the util Docker container as a transient stage; e.g., for a small calculation to add to an existing stage
# only run if the specified file does not exist yet
run-transient-unless(file=, command...) {
    if ([[ -z $file ]] || is-file-empty "$OUTPUT_DIRECTORY/$file") && [[ $DOCKER_RUN == y ]]; then
        run "" "" "$OUTPUT_DIRECTORY" bash -c "cd $DOCKER_SCRIPTS_DIRECTORY; source $TOOL.sh true; cd \"\$(input-directory)\"; $(to-list command "; ")"
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
    read-linux-names() {
        run --stage read-linux-names
    }

    # extracts architectures of linux revisions
    read-linux-architectures() {
        run --stage read-linux-architectures
    }

    # extracts configuration options of linux revisions
    read-linux-configs() {
        run --stage read-linux-configs
    }

    # extracts configuration options of toybox revisions
    read-toybox-configs() {
        run --stage read-toybox-configs
    }
    
    # extracts configuration options of axtls revisions
    read-axtls-configs() {
        run --stage read-axtls-configs
    }

    # extracts configuration options of busybox revisions
    read-busybox-configs() {
        run --stage read-busybox-configs
    }
    
    # extracts configuration options of embtoolkit revisions
    read-embtoolkit-configs() {
        run --stage read-embtoolkit-configs
    }
    
    # extracts configuration options of buildroot revisions
    read-buildroot-configs() {
        run --stage read-buildroot-configs
    }

    # extracts configuration options of fiasco revisions
    read-fiasco-configs() {
        run --stage read-fiasco-configs
    }
    
    # extracts configuration options of freetz-ng revisions 
    read-freetz-ng-configs() {
        run --stage read-freetz-ng-configs
    }
    
    # extracts configuration options of uclibc-ng revisions 
    read-uclibc-ng-configs() {
        run --stage read-uclibc-ng-configs
    }
    

    # read basic statistics for each system
    # read basic statistics for each system
    read-statistics(option=) {
        run --stage read-statistics --command read-statistics "$option"
    }

    # generate repository with full history of BusyBox
    generate-busybox-models() {
        if [[ ! -d "$(input-directory)/busybox-models" ]]; then
            run --stage busybox-models --command generate-busybox-models
            mv "$(output-directory busybox-models)" "$(input-directory)/busybox-models"
        fi
    }

    # extracts kconfig models with the given extractor
    extract-kconfig-models-with(extractor, output_stage=kconfig, iterations=1, iteration_field=iteration, file_fields=) {
        iterate \
            --stage "$output_stage" \
            --iterations "$iterations" \
            --iteration-field "$iteration_field" \
            --file-fields "$file_fields" \
            --image "$extractor" \
            --command "extract-kconfig-models-with-$extractor"
    }

    # extracts kconfig models with kconfigreader and kmax
    extract-kconfig-models(output_stage=kconfig, iterations=1, iteration_field=iteration, file_fields=) {
        extract-kconfig-models-with \
            --extractor kconfigreader \
            --output-stage kconfigreader \
            --iterations "$iterations" \
            --iteration-field "$iteration_field" \
            --file-fields "$file_fields"
        extract-kconfig-models-with \
            --extractor kmax \
            --output-stage kmax \
            --iterations "$iterations" \
            --iteration-field "$iteration_field" \
            --file-fields "$file_fields"
            
        extract-kconfig-models-with \
	    --extractor configfixextractor \
	    --output-stage configfixextractor \
	    --iterations "$iterations" \
	    --iteration-field "$iteration_field" \
	    --file-fields "$file_fields"

	file_fields="binding-file"
	if [ -z "$binding_file" ]; then
	    binding_file=""
	fi

    aggregate \
	    --stage "$output_stage" \
	    --stage-field extractor \
	    --file-fields "$binding_file",model-file\
	    --stages kconfigreader kmax configfixextractor
    }

    # transforms model files with FeatJAR
    transform-models-with-featjar(transformer, output_extension, input_stage=kconfig, command=transform-with-featjar, timeout=0, jobs=1, iterations=1, iteration_field=iteration, file_fields=) {
        # shellcheck disable=SC2128
        iterate \
            --stage "$transformer" \
            --iterations "$iterations" \
            --iteration-field "$iteration_field" \
            --file-fields "$file_fields" \
            --image featjar \
            --input-directory "$input_stage" \
            --command "$command" \
            --input-extension model \
            --output-extension "$output_extension" \
            --transformer "$transformer" \
            --timeout "$timeout" \
            --jobs "$jobs"
    }

    # transforms model files into DIMACS with FeatJAR
    transform-models-into-dimacs-with-featjar(transformer, input_stage=kconfig, timeout=0, jobs=1, iterations=1, iteration_field=iteration, file_fields=) {
        transform-models-with-featjar \
            --command transform-into-dimacs-with-featjar \
            --output-extension dimacs \
            --input-stage "$input_stage" \
            --transformer "$transformer" \
            --timeout "$timeout" \
            --jobs "$jobs" \
            --iterations "$iterations" \
            --iteration-field "$iteration_field" \
            --file-fields "$file_fields"
    }

    # transforms model files into DIMACS
    transform-models-into-dimacs(input_stage=kconfig, output_stage=dimacs, timeout=0, jobs=1) {
        # distributive tranformation
        transform-models-into-dimacs-with-featjar \
            --transformer model_to_dimacs_featureide \
            --input-stage "$input_stage" \
            --timeout "$timeout" \
            --jobs "$jobs"
        transform-models-into-dimacs-with-featjar \
            --transformer model_to_dimacs_featjar \
            --input-stage "$input_stage" \
            --timeout "$timeout" \
            --jobs "$jobs"
        
        # intermediate formats for CNF transformation
        transform-models-with-featjar \
            --transformer model_to_model_featureide \
            --output-extension featureide.model \
            --input-stage "$input_stage" \
            --timeout "$timeout" \
            --jobs "$jobs"
        transform-models-with-featjar \
            --transformer model_to_smt_z3 \
            --output-extension smt \
            --input-stage "$input_stage" \
            --timeout "$timeout" \
            --jobs "$jobs"

        # Plaisted-Greenbaum CNF tranformation
        run \
            --stage model_to_dimacs_kconfigreader \
            --image kconfigreader \
            --input-directory model_to_model_featureide \
            --command transform-into-dimacs-with-kconfigreader \
            --input-extension featureide.model \
            --timeout "$timeout" \
            --jobs "$jobs"
        join-into model_to_model_featureide model_to_dimacs_kconfigreader

        # Tseitin CNF tranformation
        run \
            --stage smt_to_dimacs_z3 \
            --image z3 \
            --input-directory model_to_smt_z3 \
            --command transform-into-dimacs-with-z3 \
            --timeout "$timeout" \
            --jobs "$jobs"
        join-into model_to_smt_z3 smt_to_dimacs_z3

        aggregate \
            --stage "$output_stage" \
            --directory-field dimacs-transformer \
            --file-fields dimacs-file \
            --stages model_to_dimacs_featureide model_to_dimacs_featjar model_to_dimacs_kconfigreader smt_to_dimacs_z3
    }

    # visualize community structure of DIMACS files as a JPEG file
    draw-community-structure(input_stage=dimacs, output_stage=community-structure, timeout=0, jobs=1) {
        run \
            --stage "$output_stage" \
            --image satgraf \
            --input-directory "$input_stage" \
            --command transform-with-satgraf \
            --timeout "$timeout" \
            --jobs "$jobs"
    }

    # compute DIMACS files with explicit backbone using kissat
    compute-backbone-dimacs-with-kissat(input_stage=dimacs, output_stage=backbone-dimacs, timeout=0, jobs=1) {
        run \
            --stage "$output_stage" \
            --image solver \
            --input-directory "$input_stage" \
            --command transform-into-backbone-dimacs-with-kissat \
            --timeout "$timeout" \
            --jobs "$jobs"
    }

    # compute DIMACS files with explicit backbone using cadiback
    compute-backbone-dimacs-with-cadiback(input_stage=dimacs, output_stage=backbone-dimacs, timeout=0, jobs=1) {
        run \
            --stage "$output_stage" \
            --image cadiback \
            --input-directory "$input_stage" \
            --command transform-into-backbone-dimacs-with-cadiback \
            --timeout "$timeout" \
            --jobs "$jobs"
    }

    # compute unconstrained features that are not mentioned in a DIMACS file
    compute-unconstrained-features(input_stage=kconfig, output_stage=unconstrained-features, timeout=0, jobs=1) {
        run \
            --stage "$output_stage" \
            --input-directory "$input_stage" \
            --command transform-into-unconstrained-features \
            --timeout "$timeout" \
            --jobs "$jobs"
    }

    # compute features in the backbone of DIMACS files
    compute-backbone-features(input_stage=backbone-dimacs, output_stage=backbone-features, timeout=0, jobs=1) {
        run \
            --stage "$output_stage" \
            --input-directory "$input_stage" \
            --command transform-into-backbone-features \
            --timeout "$timeout" \
            --jobs "$jobs"
    }

    # solve DIMACS files
    solve(kind, input_stage=dimacs, input_extension=dimacs, timeout=0, jobs=1, attempts=, attempt_grouper=, iterations=1, iteration_field=iteration, file_fields=, solver_specs...) {
        local stages=()
        for solver_spec in "${solver_specs[@]}"; do
            local solver stage image parser
            solver=$(echo "$solver_spec" | cut -d, -f1)
            stage=${solver//\//_}
            stage=solve_${stage,,}
            image=$(echo "$solver_spec" | cut -d, -f2)
            parser=$(echo "$solver_spec" | cut -d, -f3)
            stages+=("$stage")
            iterate \
                --stage "$stage" \
                --iterations "$iterations" \
                --iteration-field "$iteration_field" \
                --file-fields "$file_fields" \
                --image "$image" \
                --input-directory "$input_stage" \
                --command solve \
                --solver "$solver" \
                --kind "$kind" \
                --parser "$parser" \
                --input-extension "$input_extension" \
                --timeout "$timeout" \
                --jobs "$jobs" \
                --attempts "$attempts" \
                --attempt-grouper "$attempt_grouper"
        done
        aggregate --stage "solve_$kind" --stages "${stages[@]}"
    }

    # solve DIMACS files for satisfiability
    solve-satisfiable(input_stage=dimacs, timeout=0, jobs=1, attempts=, attempt_grouper=, iterations=1, iteration_field=iteration, file_fields=) {
        local solver_specs=(
            sat-competition/02-zchaff,solver,satisfiable
            sat-competition/03-Forklift,solver,satisfiable
            sat-competition/04-zchaff,solver,satisfiable
            sat-competition/05-SatELiteGTI.sh,solver,satisfiable
            sat-competition/06-MiniSat,solver,satisfiable
            sat-competition/07-RSat.sh,solver,satisfiable
            sat-competition/08-MiniSat,solver,satisfiable
            sat-competition/09-precosat,solver,satisfiable
            sat-competition/10-CryptoMiniSat,solver,satisfiable
            sat-competition/11-glucose.sh,solver,satisfiable
            sat-competition/12-glucose.sh,solver,satisfiable
            sat-competition/13-lingeling-aqw,solver,satisfiable
            sat-competition/14-lingeling-ayv,solver,satisfiable
            sat-competition/15-abcdSAT,solver,satisfiable
            sat-competition/16-MapleCOMSPS_DRUP,solver,satisfiable
            sat-competition/17-Maple_LCM_Dist,solver,satisfiable
            sat-competition/18-MapleLCMDistChronoBT,solver,satisfiable
            sat-competition/19-MapleLCMDiscChronoBT-DL-v3,solver,satisfiable
            sat-competition/20-Kissat-sc2020-sat,solver,satisfiable
            sat-competition/21-Kissat_MAB,solver,satisfiable
            sat-competition/22-kissat_MAB-HyWalk,solver,satisfiable
            sat-competition/23-sbva_cadical.sh,solver,satisfiable
            other/SAT4J.sh,solver,satisfiable
            z3,z3,satisfiable
        )
        solve --kind satisfiable --input-stage "$input_stage" --timeout "$timeout" --jobs "$jobs" \
            --attempts "$attempts" --attempt-grouper "$attempt_grouper" \
            --iterations "$iterations" --iteration_field "$iteration_field" --file_fields "$file_fields" \
            --solver_specs "${solver_specs[@]}"
    }

    # solve DIMACS files for model count
    solve-model-count(input_stage=dimacs, timeout=0, jobs=1, attempts=, attempt_grouper=) {
        local solver_specs=(
            emse-2023/countAntom,solver,model-count
            emse-2023/d4,solver,model-count
            emse-2023/dSharp,solver,model-count
            emse-2023/ganak,solver,model-count
            emse-2023/sharpSAT,solver,model-count
            model-counting-competition-2022/c2d.sh,solver,model-counting-competition-2022
            model-counting-competition-2022/d4.sh,solver,model-counting-competition-2022
            model-counting-competition-2022/DPMC/DPMC.sh,solver,model-counting-competition-2022
            model-counting-competition-2022/gpmc.sh,solver,model-counting-competition-2022
            model-counting-competition-2022/TwG.sh,solver,model-counting-competition-2022
            model-counting-competition-2022/SharpSAT-td+Arjun/SharpSAT-td+Arjun.sh,solver,model-counting-competition-2022
            model-counting-competition-2022/SharpSAT-TD/SharpSAT-TD.sh,solver,model-counting-competition-2022
            other/d4v2.sh,solver,model-count
            other/ApproxMC,solver,model-count
        )
        solve --kind model-count --input-stage "$input_stage" --timeout "$timeout" --jobs "$jobs" \
            --attempts "$attempts" --attempt-grouper "$attempt_grouper" --solver_specs "${solver_specs[@]}"
    }

    # logs a specific field of a given stage's output file
    log-output-field(stage, field) {
        if [[ -f $(output-csv "$stage") ]]; then
            log "$field: $(table-field "$(output-csv "$stage")" "$field" | sort | uniq | tr '\n' ' ')"
        fi
    }

    # runs a Jupyter notebook
    run-notebook(input_stage=$PWD, output_stage=notebook, file) {
        run \
            --stage "$output_stage" \
            --image jupyter \
            --input-directory "$input_stage" \
            --command run-notebook \
            --file "$file"
    }

    # build10 the given image, if necessary
    build-image(image) {
        # shellcheck disable=SC2128
        run --stage "" --image "$image" --command echo
    }
}
