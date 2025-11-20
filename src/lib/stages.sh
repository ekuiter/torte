#!/bin/bash
# convenience functions for defining commonly used stages
# we do not define these directly here to not shadow functions defined elsewhere (as these stages are only needed in the host environment)

define-stages() {
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

    # todo: generalize this
    # extracts configuration options of linux revisions
    read-linux-configs() {
        run --output read-linux-configs
    }

    # read basic statistics for each system
    read-statistics(input=, option=) {
        run --input "$input" --output read-statistics --command read-statistics "$option"
    }

    # generate repository with full history of BusyBox feature model
    generate-busybox-models() {
        run --output generate-busybox-models
    }

    # extracts kconfig models with the given extractor
    extract-kconfig-models-with(extractor, input=, output=, iterations=1, iteration_field=, options=, timeout=0) {
        output="${output:-extract-kconfig-models-with-$extractor}"
        iterate \
            --iterations "$iterations" \
            --iteration-field "$iteration_field" \
            --file-fields binding_file,model_file \
            --image "$extractor" \
            --input "$input" \
            --output "$output" \
            --resumable y \
            --command "extract-kconfig-models-with-$extractor" \
            --options "$options" \
            --timeout "$timeout"
    }

    # extracts kconfig models with kconfigreader and kclause
    extract-kconfig-models(input=, output=extract-kconfig-models, iteration_field=, options=, timeout=0, with_kconfigreader=, with_kclause=) {
        if [[ -z $with_kconfigreader ]] && [[ -z $with_kclause ]]; then
            with_kconfigreader=y
            with_kclause=y
        fi
        [[ $with_kconfigreader == n ]] && with_kconfigreader=
        [[ $with_kconfigreader == y ]] && with_kconfigreader=1
        [[ $with_kclause == n ]] && with_kclause=
        [[ $with_kclause == y ]] && with_kclause=1
        local inputs=()

        if [[ -n $with_kconfigreader ]]; then
            extract-kconfig-models-with \
                --extractor kconfigreader \
                --input "$input" \
                --iterations "$with_kconfigreader" \
                --iteration-field "$iteration_field" \
                --options "$options" \
                --timeout "$timeout"
            inputs+=("extract-kconfig-models-with-kconfigreader")
        fi

        if [[ -n $with_kclause ]]; then
            extract-kconfig-models-with \
                --extractor kclause \
                --input "$input" \
                --iterations "$with_kclause" \
                --iteration-field "$iteration_field" \
                --options "$options" \
                --timeout "$timeout"
            inputs+=("extract-kconfig-models-with-kclause")
        fi

        # extract-kconfig-models-with \
        # --extractor configfix \
        # --iterations "$iterations" \
        # --iteration-field "$iteration_field" \
            # --options "$options" \
        # --timeout "$timeout"
        # todo ConfigFix: the idea was that not every extractor needs a binding file, which is not correctly realized here, I think
        # file_fields="binding_file"
        # if [ -z "$binding_file" ]; then
        #     binding_file=""
        # fi

        aggregate \
            --output "$output" \
            --stage-field extractor \
            --file-fields binding_file,model_file \
            --inputs "${inputs[@]}"
    }

    # extracts kconfig hierarchies with kconfiglib
    extract-kconfig-hierarchies-with-kconfiglib(main_input=, uvl_input=, unconstrained_features_input=, output=extract-kconfig-hierarchies-with-kconfiglib, timeout=0) {
        run \
            --image kconfiglib \
            --input "$(mount-for-hierarchy-extraction "$main_input" "$uvl_input" "$unconstrained_features_input")" \
            --output "$output" \
            --command extract-kconfig-hierarchies-with-kconfiglib \
            --timeout "$timeout"
    }

    # transforms model files with FeatJAR
    transform-with-featjar(transformer, output_extension, input=extract-kconfig-models, command=transform-with-featjar, timeout=0, jobs=1, iterations=1, iteration_field=) {
        # shellcheck disable=SC2128
        iterate \
            --iterations "$iterations" \
            --iteration-field "$iteration_field" \
            --file-fields "${output_extension}_file" \
            --image featjar \
            --input "$input" \
            --output "$transformer" \
            --resumable y \
            --command "$command" \
            --input-extension model \
            --output-extension "$output_extension" \
            --transformer "$transformer" \
            --timeout "$timeout" \
            --jobs "$jobs"
    }

    # transforms model files to DIMACS with FeatJAR
    transform-to-dimacs-with-featjar(transformer, input=extract-kconfig-models, timeout=0, jobs=1, iterations=1, iteration_field=) {
        transform-with-featjar \
            --command transform-to-dimacs-with-featjar \
            --output-extension dimacs \
            --input "$input" \
            --transformer "$transformer" \
            --timeout "$timeout" \
            --jobs "$jobs" \
            --iterations "$iterations" \
            --iteration-field "$iteration_field"
    }

    # transforms model files to DIMACS
    # this allows to flexibly enable (repeated or single iterations of) the desired CNF transformations
    # some of these transformations are fully deterministic and need not be iterated (e.g., Z3), while KConfigReader is NOT deterministic
    transform-to-dimacs(input=extract-kconfig-models, output=transform-to-dimacs, timeout=0, jobs=1, iteration_field=, with_featureide=, with_featjar=, with_kconfigreader=, with_z3=) {
        if [[ -z $with_featureide ]] && [[ -z $with_featjar ]] && [[ -z $with_kconfigreader ]] && [[ -z $with_z3 ]]; then
            with_featureide=y
            with_featjar=y
            with_kconfigreader=y
            with_z3=y
        fi
        [[ $with_featureide == n ]] && with_featureide=
        [[ $with_featureide == y ]] && with_featureide=1
        [[ $with_featjar == n ]] && with_featjar=
        [[ $with_featjar == y ]] && with_featjar=1
        [[ $with_kconfigreader == n ]] && with_kconfigreader=
        [[ $with_kconfigreader == y ]] && with_kconfigreader=1
        [[ $with_z3 == n ]] && with_z3=
        [[ $with_z3 == y ]] && with_z3=1
        local inputs=()

        # distributive tranformation with FeatureIDE (does not scale to large formulas)
        if [[ -n $with_featureide ]]; then
            transform-to-dimacs-with-featjar \
                --transformer transform-to-dimacs-with-featureide \
                --input "$input" \
                --timeout "$timeout" \
                --jobs "$jobs" \
                --iterations "$with_featureide" \
                --iteration-field "$iteration_field"
            inputs+=("transform-to-dimacs-with-featureide")
        fi

        # distributive tranformation with FeatJAR (does not scale to large formulas)
        if [[ -n $with_featjar ]]; then
            transform-to-dimacs-with-featjar \
                --transformer transform-to-dimacs-with-featjar \
                --input "$input" \
                --timeout "$timeout" \
                --jobs "$jobs" \
                --iterations "$with_featjar" \
                --iteration-field "$iteration_field"
            inputs+=("transform-to-dimacs-with-featjar")
        fi

        if [[ -n $with_kconfigreader ]]; then
            # intermediate format for CNF transformation with KConfigReader
            transform-with-featjar \
                --transformer transform-to-model-with-featureide \
                --output-extension featureide.model \
                --input "$input" \
                --timeout "$timeout" \
                --jobs "$jobs"
            # Plaisted-Greenbaum CNF tranformation with KConfigReader (preserves satisfiability, but not model count)
            iterate \
                --iterations "$with_kconfigreader" \
                --iteration-field "$iteration_field" \
                --file-fields dimacs_file \
                --image kconfigreader \
                --input transform-to-model-with-featureide \
                --output transform-to-dimacs-with-kconfigreader \
                --resumable y \
                --command transform-to-dimacs-with-kconfigreader \
                --input-extension featureide.model \
                --timeout "$timeout" \
                --jobs "$jobs"
            join-into transform-to-model-with-featureide transform-to-dimacs-with-kconfigreader
            inputs+=("transform-to-dimacs-with-kconfigreader")
        fi

        if [[ -n $with_z3 ]]; then
            # intermediate format for CNF transformation with Z3
            transform-with-featjar \
                --transformer transform-to-smt-with-z3 \
                --output-extension smt \
                --input "$input" \
                --timeout "$timeout" \
                --jobs "$jobs"
            # Tseitin CNF tranformation with Z3 (preserves satisfiability and model count)
            iterate \
                --iterations "$with_z3" \
                --iteration-field "$iteration_field" \
                --file-fields dimacs_file \
                --image z3 \
                --input transform-to-smt-with-z3 \
                --output transform-smt-to-dimacs-with-z3 \
                --resumable y \
                --command transform-smt-to-dimacs-with-z3 \
                --timeout "$timeout" \
                --jobs "$jobs"
            join-into transform-to-smt-with-z3 transform-smt-to-dimacs-with-z3
            inputs+=("transform-smt-to-dimacs-with-z3")
        fi

        aggregate \
            --output "$output" \
            --directory-field dimacs_transformer \
            --file-fields dimacs_file \
            --inputs "${inputs[@]}"
    }

    # transforms model files to UVL
    transform-to-uvl(input=extract-kconfig-models, timeout=0, jobs=1, iterations=1, iteration_field=) {
        transform-with-featjar \
            --transformer transform-to-uvl-with-featureide \
            --output-extension uvl  \
            --input "$input" \
            --timeout "$timeout" \
            --jobs "$jobs" \
            --iterations "$iterations" \
            --iteration-field "$iteration_field"
    }

    # transforms model files to XML
    transform-to-xml(input=extract-kconfig-models, timeout=0, jobs=1, iterations=1, iteration_field=) {
        transform-with-featjar \
            --transformer transform-to-xml-with-featureide \
            --output-extension xml  \
            --input "$input" \
            --timeout "$timeout" \
            --jobs "$jobs" \
            --iterations "$iterations" \
            --iteration-field "$iteration_field"
    }

    # visualize community structure of DIMACS files as a JPEG file
    draw-community-structure-with-satgraf(input=transform-to-dimacs, output=draw-community-structure-with-satgraf, timeout=0, jobs=1) {
        run \
            --image satgraf \
            --input "$input" \
            --output "$output" \
            --resumable y \
            --command draw-community-structure-with-satgraf \
            --timeout "$timeout" \
            --jobs "$jobs"
    }

    # compute DIMACS files with explicit backbone using kissat or cadiback
    transform-dimacs-to-backbone-dimacs-with(transformer, input=transform-to-dimacs, output=transform-dimacs-to-backbone-dimacs, timeout=0, jobs=1) {
        if [[ $transformer == cadiback ]]; then
            local image=cadiback
        elif [[ $transformer == kissat ]]; then
            local image=solver
        else
            error "Unknown backbone transformer: $transformer"
        fi
        run \
            --image "$image" \
            --input "$input" \
            --output "$output" \
            --resumable y \
            --command transform-dimacs-to-backbone-dimacs-with \
            --transformer "$transformer" \
            --timeout "$timeout" \
            --jobs "$jobs"
    }

    # compute model features that mentioned in a feature model
    compute-model-features(input=extract-kconfig-models, output=compute-model-features, timeout=0, jobs=1) {
        run \
            --input "$input" \
            --output "$output" \
            --resumable y \
            --command compute-features \
            --kind model \
            --timeout "$timeout" \
            --jobs "$jobs"
    }

    # compute constrained features that are mentioned in a .model file
    compute-constrained-features(input=extract-kconfig-models, output=compute-constrained-features, timeout=0, jobs=1) {
        run \
            --input "$input" \
            --output "$output" \
            --resumable y \
            --command compute-features \
            --kind constrained \
            --timeout "$timeout" \
            --jobs "$jobs"
    }

    # compute unconstrained features that are not mentioned in a .model file
    compute-unconstrained-features(input=extract-kconfig-models, output=compute-unconstrained-features, timeout=0, jobs=1) {
        run \
            --input "$input" \
            --output "$output" \
            --resumable y \
            --command compute-features \
            --kind unconstrained \
            --timeout "$timeout" \
            --jobs "$jobs"
    }

    # compute features in the backbone of DIMACS files
    compute-backbone-features(input=transform-dimacs-to-backbone-dimacs, output=compute-backbone-features, timeout=0, jobs=1) {
        run \
            --input "$input" \
            --output "$output" \
            --resumable y \
            --command compute-features \
            --kind backbone \
            --timeout "$timeout" \
            --jobs "$jobs"
    }

    # compute a random sample of some input stage with line-delimited output (e.g., feature lists)
    compute-random-sample(input, output=compute-random-sample, extension, size=1, t_wise=1, separator=, seed=, timeout=0, jobs=1) {
        run \
            --input "$input" \
            --output "$output" \
            --resumable y \
            --command compute-random-sample \
            --extension "$extension" \
            --size "$size" \
            --t-wise "$t_wise" \
            --separator "$separator" \
            --seed "$seed" \
            --timeout "$timeout" \
            --jobs "$jobs"
    }

    # solve DIMACS files
    solve(kind, query=, input=transform-to-dimacs, input_extension=dimacs, timeout=0, jobs=1, attempts=, attempt_grouper=, query_iterator=, iterations=1, iteration_field=, file_fields=, solver_specs...) {
        local stages=()
        for solver_spec in "${solver_specs[@]}"; do
            local solver stage image parser
            solver=$(echo "$solver_spec" | cut -d, -f1)
            stage=${solver/$DOCKER_INPUT_DIRECTORY\/$SAT_HERITAGE_INPUT_KEY/}
            stage=${stage/run.sh/}
            stage=$(echo "$stage" | sed -E 's#[/_.+ ]+#-#g; s/^-+//; s/-+$//')
            stage=solve-${query:+$query-}${stage,,}
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
                --resumable y \
                --command solve \
                --solver "$solver" \
                --kind "$kind" \
                --parser "$parser" \
                --input-extension "$input_extension" \
                --timeout "$timeout" \
                --jobs "$jobs" \
                --attempts "$attempts" \
                --attempt-grouper "$attempt_grouper" \
                --query-iterator "$query_iterator"
        done
        if [[ -n $query ]]; then
            stage=$query-${stage,,}
        fi
        aggregate --output "solve-${query:+$query-}$kind" --inputs "${stages[@]}"
    }

    # solve DIMACS files for satisfiability
    # many solvers are available, which are listed below, but only few are enabled by default
    solve-sat(input=transform-to-dimacs, timeout=0, jobs=1, attempts=, attempt_grouper=, query_iterator=, iterations=1, iteration_field=, file_fields=) {
        local solver_specs=(
            sat-competition/02-zchaff,solver,sat
            sat-competition/03-Forklift,solver,sat
            sat-competition/04-zchaff,solver,sat
            sat-competition/05-SatELiteGTI.sh,solver,sat
            sat-competition/06-MiniSat,solver,sat
            sat-competition/07-RSat.sh,solver,sat
            sat-competition/08-MiniSat,solver,sat
            sat-competition/09-precosat,solver,sat
            sat-competition/10-CryptoMiniSat,solver,sat
            sat-competition/11-glucose.sh,solver,sat
            sat-competition/12-glucose.sh,solver,sat
            sat-competition/13-lingeling-aqw,solver,sat
            sat-competition/14-lingeling-ayv,solver,sat
            sat-competition/15-abcdSAT,solver,sat
            sat-competition/16-MapleCOMSPS_DRUP,solver,sat
            sat-competition/17-Maple_LCM_Dist,solver,sat
            sat-competition/18-MapleLCMDistChronoBT,solver,sat
            sat-competition/19-MapleLCMDiscChronoBT-DL-v3,solver,sat
            sat-competition/20-Kissat-sc2020-sat,solver,sat
            sat-competition/21-Kissat_MAB,solver,sat
            sat-competition/22-kissat_MAB-HyWalk,solver,sat
            sat-competition/23-sbva_cadical.sh,solver,sat
            sat-competition/24-kissat-sc2024,solver,sat
            sat-museum/boehm1-1992,solver,sat
            sat-museum/grasp-1997,solver,sat
            sat-museum/chaff-2001,solver,sat
            sat-museum/limmat-2002,solver,sat
            sat-museum/berkmin-2003.sh,solver,sat
            sat-museum/zchaff-2004,solver,sat
            sat-museum/satelite-gti-2005.sh,solver,sat
            sat-museum/minisat-2006,solver,sat
            sat-museum/rsat-2007.sh,solver,sat
            sat-museum/minisat-2008,solver,sat
            sat-museum/precosat-2009,solver,sat
            sat-museum/cryptominisat-2010,solver,sat
            sat-museum/glucose-2011.sh,solver,sat
            sat-museum/glucose-2012.sh,solver,sat
            sat-museum/lingeling-2013,solver,sat
            sat-museum/lingeling-2014,solver,sat
            sat-museum/abcdsat-2015.sh,solver,sat
            sat-museum/maple-comsps-drup-2016,solver,sat
            sat-museum/maple-lcm-dist-2017,solver,sat
            sat-museum/maple-lcm-dist-cb-2018,solver,sat
            sat-museum/maple-lcm-disc-cb-dl-v3-2019,solver,sat
            sat-museum/kissat-2020,solver,sat
            sat-museum/kissat-mab-2021,solver,sat
            sat-museum/kissat-mab-hywalk-2022,solver,sat
            other/SAT4J.210.sh,solver,sat
            other/SAT4J.231.sh,solver,sat
            other/SAT4J.235.sh,solver,sat
            other/SAT4J.236.sh,solver,sat
            z3,z3,sat
        )
        solve --kind sat --input "$input" --timeout "$timeout" --jobs "$jobs" \
            --attempts "$attempts" --attempt-grouper "$attempt_grouper" \
            --query-iterator "$query_iterator" \
            --iterations "$iterations" --iteration_field "$iteration_field" --file_fields "$file_fields" \
            --solver_specs "${solver_specs[@]}"
    }

    # solve DIMACS files for model count
    # many solvers are available, which are listed below, but only few are enabled by default
    solve-sharp-sat(input=transform-to-dimacs, timeout=0, jobs=1, attempts=, attempt_grouper=, query_iterator=, iterations=1, iteration_field=, file_fields=) {
        local solver_specs=(
            emse-2023/countAntom,solver,sharp-sat
            emse-2023/d4,solver,sharp-sat
            emse-2023/dSharp,solver,sharp-sat
            emse-2023/ganak,solver,sharp-sat
            emse-2023/sharpSAT,solver,sharp-sat
            mcc-2022/c2d.sh,solver,sharp-sat-mcc22
            mcc-2022/d4.sh,solver,sharp-sat-mcc22
            mcc-2022/DPMC/DPMC.sh,solver,sharp-sat-mcc22
            mcc-2022/gpmc.sh,solver,sharp-sat-mcc22
            mcc-2022/TwG.sh,solver,sharp-sat-mcc22
            mcc-2022/SharpSAT-td+Arjun/SharpSAT-td+Arjun.sh,solver,sharp-sat-mcc22
            mcc-2022/SharpSAT-TD/SharpSAT-TD.sh,solver,sharp-sat-mcc22
            other/d4v2.sh,solver,sharp-sat
            other/ApproxMC,solver,sharp-sat
        )
        solve --kind sharp-sat --input "$input" --timeout "$timeout" --jobs "$jobs" \
            --attempts "$attempts" --attempt-grouper "$attempt_grouper" \
            --query-iterator "$query_iterator" \
            --iterations "$iterations" --iteration_field "$iteration_field" --file_fields "$file_fields" \
            --solver_specs "${solver_specs[@]}"
    }

    # logs a specific field of a given stage's output file
    log-output-field(stage, field) {
        if [[ -f $(stage-csv "$stage") ]]; then
            log "$field: $(table-field "$(stage-csv "$stage")" "$field" | sort | uniq | tr '\n' ' ')"
        fi
    }

    # runs a Jupyter notebook
    run-jupyter-notebook(input=, output=run-jupyter-notebook, payload_file, to=html, options=) {
        run \
            --image jupyter \
            --input "$input" \
            --output "$output" \
            --command run-jupyter-notebook \
            --payload-file "$payload_file" \
            --to "$to" \
            --options "$options"
    }

    # build the given image, if necessary
    build-image(image) {
        # shellcheck disable=SC2128
        run --image "$image" --output "" --command echo
    }
}