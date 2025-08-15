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
            mkdir -p "$(stage-directory "$output")"
            chmod 0777 "$(stage-directory "$output")"
            log "" "$(echo-progress run)"
            mkdir -p "$STAGE_DIRECTORY/$CACHE_DIRECTORY" # todo: possibly eliminate this?
            mv "$STAGE_DIRECTORY/$CACHE_DIRECTORY" "$(stage-directory "$output")/$CACHE_DIRECTORY"
            local cmd=(docker run)
            if [[ $DEBUG == y ]]; then
                command=(/bin/bash)
            fi
            if [[ ${command[*]} == /bin/bash ]]; then
                cmd+=(-it)
            fi

            if [[ $output != clone-systems ]]; then
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
            output_volume=$(stage-directory "$output")
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
                    > >(write-all "$(stage-log "$output")") \
                    2> >(write-all "$(stage-err "$output")" >&2)
                FORCE_NEW_LOG=y
            fi
            mv "$(stage-directory "$output")/$CACHE_DIRECTORY" "$STAGE_DIRECTORY/$CACHE_DIRECTORY"
            rm-if-empty "$(stage-log "$output")"
            rm-if-empty "$(stage-err "$output")"
            find "$(stage-directory "$output")" -mindepth 1 -type d -empty -delete
            touch "$(stage-done-file "$output")"
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
            local current_stage="${output}_$i"
            stages+=("$current_stage")
            run "$image" "$input" "$current_stage" "${command[@]}"
        done
        if [[ ! -f "$(stage-csv "${output}_1")" ]]; then
            error "Required output CSV for stage ${output}_1 is missing, please re-run stage ${output}_1."
        fi
        aggregate "$output" "$file_fields" "$iteration_field" "$(lambda value "echo \$value | rev | cut -d_ -f1 | rev")" "" "${stages[@]}"
    fi
}

# runs the util Docker container as a transient stage; e.g., for a small calculation to add to an existing stage
# only run if the specified file does not exist yet
# should be run before the existing stage is moved (e.g., by an aggregation)
run-transient-unless(file=, input=, command...) {
    local file_path="$STAGE_DIRECTORY/$file"
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
    if ([[ -z $file ]] || is-file-empty "$file_path") && [[ $DOCKER_RUN == y ]]; then
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
    if [[ ! -f $stage ]] && [[ -f $(stage-csv "$stage") ]]; then
        file=$(stage-csv "$stage")
    else
        file=$stage
    fi
    run-transient-unless "" "plot-helper \"${file#"$STAGE_DIRECTORY/"}\" \"$type\" \"$fields\" ${arguments[*]}"
}

# convenience functions for defining commonly used stages
# we do not define these directly here to not shadow functions defined elsewhere (as these stages are only needed in the host environment)
define-stage-helpers() {
    # clone the systems specified in the experiment file
    clone-systems() {
        run --output clone-systems
    }

    # tag old Linux revisions that are not included in its Git history
    tag-linux-revisions(option=) {
        run --output tag-linux-revisions --command tag-linux-revisions "$option"
    }

    # extracts code names of linux revisions
    read-linux-names() {
        run --output read-linux-names
    }

    # extracts architectures of linux revisions
    read-linux-architectures() {
        run --output read-linux-architectures
    }

    # to do: remove/unify these
    # extracts configuration options of linux revisions
    read-linux-configs() {
        run --output read-linux-configs
    }

    # extracts configuration options of toybox revisions
    read-toybox-configs() {
        run --output read-toybox-configs
    }
    
    # extracts configuration options of axtls revisions
    read-axtls-configs() {
        run --output read-axtls-configs
    }

    # extracts configuration options of busybox revisions
    read-busybox-configs() {
        run --output read-busybox-configs
    }
    
    # extracts configuration options of embtoolkit revisions
    read-embtoolkit-configs() {
        run --output read-embtoolkit-configs
    }
    
    # extracts configuration options of buildroot revisions
    read-buildroot-configs() {
        run --output read-buildroot-configs
    }

    # extracts configuration options of fiasco revisions
    read-fiasco-configs() {
        run --output read-fiasco-configs
    }
    
    # extracts configuration options of freetz-ng revisions 
    read-freetz-ng-configs() {
        run --output read-freetz-ng-configs
    }
    
    # extracts configuration options of uclibc-ng revisions 
    read-uclibc-ng-configs() {
        run --output read-uclibc-ng-configs
    }

    # read basic statistics for each system
    read-statistics(option=) {
        run --output read-statistics --command read-statistics "$option"
    }

    # generate repository with full history of BusyBox
    generate-busybox-models() {
        if [[ ! -d "$(input-directory)/busybox-models" ]]; then
            run --output busybox-models --command generate-busybox-models
            mv "$(stage-directory busybox-models)" "$(input-directory)/busybox-models" # todo: does output/input directory work here?
        fi
    }

    # extracts kconfig models with the given extractor
    extract-kconfig-models-with(extractor, output_stage=kconfig, iterations=1, iteration_field=iteration, file_fields=) {
        iterate \
            --iterations "$iterations" \
            --iteration-field "$iteration_field" \
            --file-fields "$file_fields" \
            --image "$extractor" \
            --output "$output_stage" \
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
            --output "$output_stage" \
            --stage-field extractor \
            --file-fields binding-file,model-file \
            --inputs kconfigreader kclause
            # --inputs kconfigreader kclause configfix
    }

    # transforms model files with FeatJAR
    transform-models-with-featjar(transformer, output_extension, input=kconfig, command=transform-with-featjar, timeout=0, jobs=1, iterations=1, iteration_field=iteration, file_fields=) {
        # shellcheck disable=SC2128
        iterate \
            --iterations "$iterations" \
            --iteration-field "$iteration_field" \
            --file-fields "$file_fields" \
            --image featjar \
            --input "$input" \
            --output "$transformer" \
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
            --image kconfigreader \
            --input model_to_model_featureide \
            --output model_to_dimacs_kconfigreader \
            --command transform-into-dimacs-with-kconfigreader \
            --input-extension featureide.model \
            --timeout "$timeout" \
            --jobs "$jobs"
        join-into model_to_model_featureide model_to_dimacs_kconfigreader

        # Tseitin CNF tranformation
        run \
            --image z3 \
            --input model_to_smt_z3 \
            --output smt_to_dimacs_z3 \
            --command transform-into-dimacs-with-z3 \
            --timeout "$timeout" \
            --jobs "$jobs"
        join-into model_to_smt_z3 smt_to_dimacs_z3

        aggregate \
            --output "$output_stage" \
            --directory-field dimacs-transformer \
            --file-fields dimacs-file \
            --inputs model_to_dimacs_featureide model_to_dimacs_featjar model_to_dimacs_kconfigreader smt_to_dimacs_z3
    }

    # visualize community structure of DIMACS files as a JPEG file
    draw-community-structure(input=dimacs, output_stage=community-structure, timeout=0, jobs=1) {
        run \
            --image satgraf \
            --input "$input" \
            --output "$output_stage" \
            --command transform-with-satgraf \
            --timeout "$timeout" \
            --jobs "$jobs"
    }

    # compute DIMACS files with explicit backbone using kissat
    compute-backbone-dimacs-with-kissat(input=dimacs, output_stage=backbone-dimacs, timeout=0, jobs=1) {
        run \
            --image solver \
            --input "$input" \
            --output "$output_stage" \
            --command transform-into-backbone-dimacs-with-kissat \
            --timeout "$timeout" \
            --jobs "$jobs"
    }

    # compute DIMACS files with explicit backbone using cadiback
    compute-backbone-dimacs-with-cadiback(input=dimacs, output_stage=backbone-dimacs, timeout=0, jobs=1) {
        run \
            --image cadiback \
            --input "$input" \
            --output "$output_stage" \
            --command transform-into-backbone-dimacs-with-cadiback \
            --timeout "$timeout" \
            --jobs "$jobs"
    }

    # compute unconstrained features that are not mentioned in a DIMACS file
    compute-unconstrained-features(input=kconfig, output_stage=unconstrained-features, timeout=0, jobs=1) {
        run \
            --input "$input" \
            --output "$output_stage" \
            --command transform-into-unconstrained-features \
            --timeout "$timeout" \
            --jobs "$jobs"
    }

    # compute features in the backbone of DIMACS files
    compute-backbone-features(input=backbone-dimacs, output_stage=backbone-features, timeout=0, jobs=1) {
        run \
            --input "$input" \
            --output "$output_stage" \
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
                --iterations "$iterations" \
                --iteration-field "$iteration_field" \
                --file-fields "$file_fields" \
                --image "$image" \
                --input "$input" \
                --output "$stage" \
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
        aggregate --output "solve_$kind" --inputs "${stages[@]}"
    }

    # solve DIMACS files for satisfiability
    # many solvers are available, which are listed below, but only few are enabled by default
    solve-satisfiable(input=dimacs, timeout=0, jobs=1, attempts=, attempt_grouper=, iterations=1, iteration_field=iteration, file_fields=) {
        local solver_specs=(
            # sat-competition/02-zchaff,solver,satisfiable
            # sat-competition/03-Forklift,solver,satisfiable
            # sat-competition/04-zchaff,solver,satisfiable
            # sat-competition/05-SatELiteGTI.sh,solver,satisfiable
            sat-competition/06-MiniSat,solver,satisfiable
            # sat-competition/07-RSat.sh,solver,satisfiable
            # sat-competition/08-MiniSat,solver,satisfiable
            # sat-competition/09-precosat,solver,satisfiable
            # sat-competition/10-CryptoMiniSat,solver,satisfiable
            # sat-competition/11-glucose.sh,solver,satisfiable
            # sat-competition/12-glucose.sh,solver,satisfiable
            # sat-competition/13-lingeling-aqw,solver,satisfiable
            # sat-competition/14-lingeling-ayv,solver,satisfiable
            # sat-competition/15-abcdSAT,solver,satisfiable
            # sat-competition/16-MapleCOMSPS_DRUP,solver,satisfiable
            # sat-competition/17-Maple_LCM_Dist,solver,satisfiable
            # sat-competition/18-MapleLCMDistChronoBT,solver,satisfiable
            # sat-competition/19-MapleLCMDiscChronoBT-DL-v3,solver,satisfiable
            # sat-competition/20-Kissat-sc2020-sat,solver,satisfiable
            # sat-competition/21-Kissat_MAB,solver,satisfiable
            sat-competition/22-kissat_MAB-HyWalk,solver,satisfiable
            # sat-competition/23-sbva_cadical.sh,solver,satisfiable
            # sat-competition/24-kissat-sc2024,solver,satisfiable
            # sat-museum/boehm1-1992,solver,satisfiable
            # sat-museum/grasp-1997,solver,satisfiable
            # sat-museum/chaff-2001,solver,satisfiable
            # sat-museum/limmat-2002,solver,satisfiable
            # sat-museum/berkmin-2003.sh,solver,satisfiable
            # sat-museum/zchaff-2004,solver,satisfiable
            # sat-museum/satelite-gti-2005.sh,solver,satisfiable
            # sat-museum/minisat-2006,solver,satisfiable
            # sat-museum/rsat-2007.sh,solver,satisfiable
            # sat-museum/minisat-2008,solver,satisfiable
            # sat-museum/precosat-2009,solver,satisfiable
            # sat-museum/cryptominisat-2010,solver,satisfiable
            # sat-museum/glucose-2011.sh,solver,satisfiable
            # sat-museum/glucose-2012.sh,solver,satisfiable
            # sat-museum/lingeling-2013,solver,satisfiable
            # sat-museum/lingeling-2014,solver,satisfiable
            # sat-museum/abcdsat-2015.sh,solver,satisfiable
            # sat-museum/maple-comsps-drup-2016,solver,satisfiable
            # sat-museum/maple-lcm-dist-2017,solver,satisfiable
            # sat-museum/maple-lcm-dist-cb-2018,solver,satisfiable
            # sat-museum/maple-lcm-disc-cb-dl-v3-2019,solver,satisfiable
            # sat-museum/kissat-2020,solver,satisfiable
            # sat-museum/kissat-mab-2021,solver,satisfiable
            # sat-museum/kissat-mab-hywalk-2022,solver,satisfiable
            # other/SAT4J.210.sh,solver,satisfiable
            # other/SAT4J.231.sh,solver,satisfiable
            # other/SAT4J.235.sh,solver,satisfiable
            # other/SAT4J.236.sh,solver,satisfiable
            z3,z3,satisfiable
        )
        solve --kind satisfiable --input "$input" --timeout "$timeout" --jobs "$jobs" \
            --attempts "$attempts" --attempt-grouper "$attempt_grouper" \
            --iterations "$iterations" --iteration_field "$iteration_field" --file_fields "$file_fields" \
            --solver_specs "${solver_specs[@]}"
    }

    # solve DIMACS files for model count
    # many solvers are available, which are listed below, but only few are enabled by default
    solve-model-count(input=dimacs, timeout=0, jobs=1, attempts=, attempt_grouper=) {
        local solver_specs=(
            # emse-2023/countAntom,solver,model-count
            # emse-2023/d4,solver,model-count
            # emse-2023/dSharp,solver,model-count
            # emse-2023/ganak,solver,model-count
            # emse-2023/sharpSAT,solver,model-count
            # model-counting-competition-2022/c2d.sh,solver,model-counting-competition-2022
            # model-counting-competition-2022/d4.sh,solver,model-counting-competition-2022
            # model-counting-competition-2022/DPMC/DPMC.sh,solver,model-counting-competition-2022
            # model-counting-competition-2022/gpmc.sh,solver,model-counting-competition-2022
            # model-counting-competition-2022/TwG.sh,solver,model-counting-competition-2022
            model-counting-competition-2022/SharpSAT-td+Arjun/SharpSAT-td+Arjun.sh,solver,model-counting-competition-2022
            # model-counting-competition-2022/SharpSAT-TD/SharpSAT-TD.sh,solver,model-counting-competition-2022
            other/d4v2.sh,solver,model-count
            # other/ApproxMC,solver,model-count
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
            --image jupyter \
            --input "$input" \
            --output "$output_stage" \
            --command run-notebook \
            --file "$file"
    }

    # build10 the given image, if necessary
    build-image(image) {
        # shellcheck disable=SC2128
        run --image "$image" --output "" --command echo
    }
}