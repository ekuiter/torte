#!/bin/bash
# runs stages

# name for transient stages
TRANSIENT_STAGE=transient

# removes all output for the given experiment stage
clean(stages...) {
    assert-array stages
    assert-host
    for stage in "${stages[@]}"; do
        rm-safe "$(stage-directory "$stage")"
    done
}

# runs a stage of some experiment in a Docker container
run(stage=, image=util, input=, command...) {
    stage=${stage:-$TRANSIENT_STAGE}
    assert-host
    local readable_stage=$stage
    if [[ $stage == "$TRANSIENT_STAGE" ]]; then
        readable_stage="<transient>"
        clean "$stage"
    fi
    log "$readable_stage"
    if [[ $FORCE_RUN == y ]] || ! stage-done "$stage"; then
        local dockerfile=$DOCKER_DIRECTORY/$image/Dockerfile
        if [[ ! -f $dockerfile ]]; then
            error "Could not find Dockerfile for image $image."
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
            mkdir -p "$(stage-directory "$stage")"
            chmod 0777 "$(stage-directory "$stage")"
            log "" "$(echo-progress run)"
            mkdir -p "$OUTPUT_DIRECTORY/$CACHE_DIRECTORY" # todo: possibly eliminate this?
            mv "$OUTPUT_DIRECTORY/$CACHE_DIRECTORY" "$(stage-directory "$stage")/$CACHE_DIRECTORY"
            local cmd=(docker run)
            if [[ $DEBUG == y ]]; then
                command=(/bin/bash)
            fi
            if [[ ${command[*]} == /bin/bash ]]; then
                cmd+=(-it)
            fi

            if [[ $stage != clone-systems ]]; then
                input=${input:-main=clone-systems}
            fi
            if [[ -n $input ]] && [[ $input != *=* ]] && stage-done "$input"; then
                input="main=$input"
            fi
            input_directories=$(echo "$input" | tr "," "\n")
            for input_directory_pair in $input_directories; do
                local key=${input_directory_pair%%=*}
                local input_directory=${input_directory_pair##*=}
                input_directory=$(stage-directory "$input_directory")
                local input_volume=$input_directory
                if [[ $input_volume != /* ]]; then
                    input_volume=$PWD/$input_volume
                fi
                cmd+=(-v "$input_volume:$DOCKER_INPUT_DIRECTORY/$key")
            done
            local output_volume
            output_volume=$(stage-directory "$stage")
            if [[ $output_volume != /* ]]; then
                output_volume=$PWD/$output_volume
            fi
            cmd+=(-v "$output_volume:$DOCKER_OUTPUT_DIRECTORY")
            cmd+=(-v "$(realpath "$SRC_DIRECTORY"):$DOCKER_SRC_DIRECTORY")

            cmd+=(-e INSIDE_DOCKER_CONTAINER=y)
            cmd+=(-e PASS) # todo: possibly eliminate this?
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
                    > >(write-all "$(stage-log "$stage")") \
                    2> >(write-all "$(stage-err "$stage")" >&2)
                FORCE_NEW_LOG=y
            fi
            mv "$(stage-directory "$stage")/$CACHE_DIRECTORY" "$OUTPUT_DIRECTORY/$CACHE_DIRECTORY"
            rm-if-empty "$(stage-log "$stage")"
            rm-if-empty "$(stage-err "$stage")"
            find "$(stage-directory "$stage")" -mindepth 1 -type d -empty -delete
            touch "$(stage-done-file "$stage")"
            if [[ $stage == "$TRANSIENT_STAGE" ]]; then
                clean "$stage"
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
        log "" "$(echo-done)"
    else
        log "" "$(echo-skip)"
    fi
}

# skips a stage, useful to comment out a stage temporarily
skip(stage=, image=util, input=, command...) {
    echo "Skipping stage $stage"
}

# merges the output files of two or more stages in a new stage
# assumes that the input directory is the root output directory, also makes some assumptions about its layout
aggregate-helper(file_fields=, stage_field=, stage_transformer=, directory_field=, stages...) {
    directory_field=${directory_field:-$stage_field}
    stage_transformer=${stage_transformer:-$(lambda-identity)}
    assert-array stages
    compile-lambda stage-transformer "$stage_transformer"
    source_transformer="$(lambda value "stage-transformer \$(basename \$(dirname \$value))")"
    csv_files=()
    for stage in "${stages[@]}"; do
        csv_files+=("$(input-directory "$stage")/$OUTPUT_FILE_PREFIX.csv")
        while IFS= read -r -d $'\0' file; do
            cp "$file" "$(output-path "$(stage-transformer "$stage")" "${file#"$(input-directory "$stage")/"}")"
        done < <(find "$(input-directory "$stage")" -type f -print0)
    done
    aggregate-tables "$stage_field" "$source_transformer" "${csv_files[@]}" > "$(output-csv)"
    tmp=$(mktemp)
    mutate-table-field "$(output-csv)" "$file_fields" "$directory_field" "$(lambda value,context_value echo "\$context_value\$PATH_SEPARATOR\$value")" > "$tmp"
    cp "$tmp" "$(output-csv)"
    rm-safe "$tmp"
}

# merges the output files of two or more stages in a new stage
aggregate(stage, file_fields=, stage_field=, stage_transformer=, directory_field=, stages...) {
    local current_stage input
    if ! stage-done "$stage"; then
        for current_stage in "${stages[@]}"; do
            assert-stage-done "$current_stage"
        done
    fi
    for current_stage in "${stages[@]}"; do
        input=$input,$current_stage=$current_stage
    done
    input=${input#,}
    run "$stage" "" "$input" aggregate-helper "$file_fields" "$stage_field" "$stage_transformer" "$directory_field" "${stages[@]}"
}

# runs a stage a given number of time and merges the output files in a new stage
iterate(stage, iterations, iteration_field=iteration, file_fields=, image=util, input=, command...) {
    if [[ $iterations -lt 1 ]]; then
        error "At least one iteration is required for stage $stage."
    fi
    if [[ $iterations -eq 1 ]]; then
        run "$stage" "$image" "$input" "${command[@]}"
    else
        local stages=()
        local i
        for i in $(seq "$iterations"); do
            local current_stage="${stage}_$i"
            stages+=("$current_stage")
            run "$current_stage" "$image" "$input" "${command[@]}"
        done
        if [[ ! -f "$(stage-csv "${stage}_1")" ]]; then
            error "Required output CSV for stage ${stage}_1 is missing, please re-run stage ${stage}_1."
        fi
        aggregate "$stage" "$file_fields" "$iteration_field" "$(lambda value "echo \$value | rev | cut -d_ -f1 | rev")" "" "${stages[@]}"
    fi
}

# runs the util Docker container as a transient stage; e.g., for a small calculation to add to an existing stage
# only run if the specified file does not exist yet
run-transient-unless(file=, input=, command...) {
    if ([[ -z $file ]] || is-file-empty "$OUTPUT_DIRECTORY/$file") && [[ $DOCKER_RUN == y ]]; then
        run "" "" "$input" bash -c "cd $DOCKER_SRC_DIRECTORY; source main.sh true; $(to-list command "; ")"
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
    if [[ ! -f $stage ]] && [[ -f $OUTPUT_DIRECTORY/$stage/$OUTPUT_FILE_PREFIX.csv ]]; then
        file=$OUTPUT_DIRECTORY/$stage/$OUTPUT_FILE_PREFIX.csv
    else
        file=$stage
    fi
    run-transient-unless "" "plot-helper \"${file#"$OUTPUT_DIRECTORY/"}\" \"$type\" \"$fields\" ${arguments[*]}"
}

# convenience functions for defining commonly used stages
# we do not define these directly here to not shadow functions defined elsewhere (as these stages are only needed in the host environment)
define-stage-helpers() {
    # clone the systems specified in the experiment file
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

    # to do: remove/unify these
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
    read-statistics(option=) {
        run --stage read-statistics --command read-statistics "$option"
    }

    # generate repository with full history of BusyBox
    generate-busybox-models() {
        if [[ ! -d "$(input-directory)/busybox-models" ]]; then
            run --stage busybox-models --command generate-busybox-models
            mv "$(output-directory busybox-models)" "$(input-directory)/busybox-models" # todo: does output/input directory work here?
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

    # extracts kconfig models with kconfigreader and kclause
    extract-kconfig-models(output_stage=kconfig, iterations=1, iteration_field=iteration, file_fields=) {
        extract-kconfig-models-with \
            --extractor kconfigreader \
            --output-stage kconfigreader \
            --iterations "$iterations" \
            --iteration-field "$iteration_field" \
            --file-fields "$file_fields"
        extract-kconfig-models-with \
            --extractor kclause \
            --output-stage kclause \
            --iterations "$iterations" \
            --iteration-field "$iteration_field" \
            --file-fields "$file_fields"
        # extract-kconfig-models-with \
        # --extractor configfix \
        # --output-stage configfix \
        # --iterations "$iterations" \
        # --iteration-field "$iteration_field" \
        # --file-fields "$file_fields"
        # todo ConfigFix: the idea was that not every extractor needs a binding file, which is not correctly realized here, I think
        # file_fields="binding-file"
        # if [ -z "$binding_file" ]; then
        #     binding_file=""
        # fi
        aggregate \
            --stage "$output_stage" \
            --stage-field extractor \
            --file-fields binding-file,model-file \
            --stages kconfigreader kclause
            # --stages kconfigreader kclause configfix
    }

    # transforms model files with FeatJAR
    transform-models-with-featjar(transformer, output_extension, input=kconfig, command=transform-with-featjar, timeout=0, jobs=1, iterations=1, iteration_field=iteration, file_fields=) {
        # shellcheck disable=SC2128
        iterate \
            --stage "$transformer" \
            --iterations "$iterations" \
            --iteration-field "$iteration_field" \
            --file-fields "$file_fields" \
            --image featjar \
            --input "$input" \
            --command "$command" \
            --input-extension model \
            --output-extension "$output_extension" \
            --transformer "$transformer" \
            --timeout "$timeout" \
            --jobs "$jobs"
    }

    # transforms model files into DIMACS with FeatJAR
    transform-models-into-dimacs-with-featjar(transformer, input=kconfig, timeout=0, jobs=1, iterations=1, iteration_field=iteration, file_fields=) {
        transform-models-with-featjar \
            --command transform-into-dimacs-with-featjar \
            --output-extension dimacs \
            --input "$input" \
            --transformer "$transformer" \
            --timeout "$timeout" \
            --jobs "$jobs" \
            --iterations "$iterations" \
            --iteration-field "$iteration_field" \
            --file-fields "$file_fields"
    }

    # transforms model files into DIMACS
    transform-models-into-dimacs(input=kconfig, output_stage=dimacs, timeout=0, jobs=1) {
        # distributive tranformation
        transform-models-into-dimacs-with-featjar \
            --transformer model_to_dimacs_featureide \
            --input "$input" \
            --timeout "$timeout" \
            --jobs "$jobs"
        transform-models-into-dimacs-with-featjar \
            --transformer model_to_dimacs_featjar \
            --input "$input" \
            --timeout "$timeout" \
            --jobs "$jobs"
        
        # intermediate formats for CNF transformation
        transform-models-with-featjar \
            --transformer model_to_model_featureide \
            --output-extension featureide.model \
            --input "$input" \
            --timeout "$timeout" \
            --jobs "$jobs"
        transform-models-with-featjar \
            --transformer model_to_smt_z3 \
            --output-extension smt \
            --input "$input" \
            --timeout "$timeout" \
            --jobs "$jobs"

        # Plaisted-Greenbaum CNF tranformation
        run \
            --stage model_to_dimacs_kconfigreader \
            --image kconfigreader \
            --input model_to_model_featureide \
            --command transform-into-dimacs-with-kconfigreader \
            --input-extension featureide.model \
            --timeout "$timeout" \
            --jobs "$jobs"
        join-into model_to_model_featureide model_to_dimacs_kconfigreader

        # Tseitin CNF tranformation
        run \
            --stage smt_to_dimacs_z3 \
            --image z3 \
            --input model_to_smt_z3 \
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
    draw-community-structure(input=dimacs, output_stage=community-structure, timeout=0, jobs=1) {
        run \
            --stage "$output_stage" \
            --image satgraf \
            --input "$input" \
            --command transform-with-satgraf \
            --timeout "$timeout" \
            --jobs "$jobs"
    }

    # compute DIMACS files with explicit backbone using kissat
    compute-backbone-dimacs-with-kissat(input=dimacs, output_stage=backbone-dimacs, timeout=0, jobs=1) {
        run \
            --stage "$output_stage" \
            --image solver \
            --input "$input" \
            --command transform-into-backbone-dimacs-with-kissat \
            --timeout "$timeout" \
            --jobs "$jobs"
    }

    # compute DIMACS files with explicit backbone using cadiback
    compute-backbone-dimacs-with-cadiback(input=dimacs, output_stage=backbone-dimacs, timeout=0, jobs=1) {
        run \
            --stage "$output_stage" \
            --image cadiback \
            --input "$input" \
            --command transform-into-backbone-dimacs-with-cadiback \
            --timeout "$timeout" \
            --jobs "$jobs"
    }

    # compute unconstrained features that are not mentioned in a DIMACS file
    compute-unconstrained-features(input=kconfig, output_stage=unconstrained-features, timeout=0, jobs=1) {
        run \
            --stage "$output_stage" \
            --input "$input" \
            --command transform-into-unconstrained-features \
            --timeout "$timeout" \
            --jobs "$jobs"
    }

    # compute features in the backbone of DIMACS files
    compute-backbone-features(input=backbone-dimacs, output_stage=backbone-features, timeout=0, jobs=1) {
        run \
            --stage "$output_stage" \
            --input "$input" \
            --command transform-into-backbone-features \
            --timeout "$timeout" \
            --jobs "$jobs"
    }

    # solve DIMACS files
    solve(kind, input=dimacs, input_extension=dimacs, timeout=0, jobs=1, attempts=, attempt_grouper=, iterations=1, iteration_field=iteration, file_fields=, solver_specs...) {
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
                --input "$input" \
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
    solve-satisfiable(input=dimacs, timeout=0, jobs=1, attempts=, attempt_grouper=, iterations=1, iteration_field=iteration, file_fields=) {
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
            sat-competition/24-kissat-sc2024,solver,satisfiable
            sat-museum/boehm1-1992,solver,satisfiable
            sat-museum/grasp-1997,solver,satisfiable
            sat-museum/chaff-2001,solver,satisfiable
            sat-museum/limmat-2002,solver,satisfiable
            sat-museum/berkmin-2003.sh,solver,satisfiable
            sat-museum/zchaff-2004,solver,satisfiable
            sat-museum/satelite-gti-2005.sh,solver,satisfiable
            sat-museum/minisat-2006,solver,satisfiable
            sat-museum/rsat-2007.sh,solver,satisfiable
            sat-museum/minisat-2008,solver,satisfiable
            sat-museum/precosat-2009,solver,satisfiable
            sat-museum/cryptominisat-2010,solver,satisfiable
            sat-museum/glucose-2011.sh,solver,satisfiable
            sat-museum/glucose-2012.sh,solver,satisfiable
            sat-museum/lingeling-2013,solver,satisfiable
            sat-museum/lingeling-2014,solver,satisfiable
            sat-museum/abcdsat-2015.sh,solver,satisfiable
            sat-museum/maple-comsps-drup-2016,solver,satisfiable
            sat-museum/maple-lcm-dist-2017,solver,satisfiable
            sat-museum/maple-lcm-dist-cb-2018,solver,satisfiable
            sat-museum/maple-lcm-disc-cb-dl-v3-2019,solver,satisfiable
            sat-museum/kissat-2020,solver,satisfiable
            sat-museum/kissat-mab-2021,solver,satisfiable
            sat-museum/kissat-mab-hywalk-2022,solver,satisfiable
            other/SAT4J.210.sh,solver,satisfiable
            other/SAT4J.231.sh,solver,satisfiable
            other/SAT4J.235.sh,solver,satisfiable
            other/SAT4J.236.sh,solver,satisfiable
            z3,z3,satisfiable
        )
        solve --kind satisfiable --input "$input" --timeout "$timeout" --jobs "$jobs" \
            --attempts "$attempts" --attempt-grouper "$attempt_grouper" \
            --iterations "$iterations" --iteration_field "$iteration_field" --file_fields "$file_fields" \
            --solver_specs "${solver_specs[@]}"
    }

    # solve DIMACS files for model count
    solve-model-count(input=dimacs, timeout=0, jobs=1, attempts=, attempt_grouper=) {
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
        solve --kind model-count --input "$input" --timeout "$timeout" --jobs "$jobs" \
            --attempts "$attempts" --attempt-grouper "$attempt_grouper" --solver_specs "${solver_specs[@]}"
    }

    # logs a specific field of a given stage's output file
    log-output-field(stage, field) {
        if [[ -f $(stage-csv "$stage") ]]; then
            log "$field: $(table-field "$(stage-csv "$stage")" "$field" | sort | uniq | tr '\n' ' ')"
        fi
    }

    # runs a Jupyter notebook
    # todo: revise this
    run-notebook(input=, output_stage=notebook, file) {
        input=${input:-$PWD}
        run \
            --stage "$output_stage" \
            --image jupyter \
            --input "$input" \
            --command run-notebook \
            --file "$file"
    }

    # build10 the given image, if necessary
    build-image(image) {
        # shellcheck disable=SC2128
        run --stage "" --image "$image" --command echo
    }
}