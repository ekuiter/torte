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
    extract-kconfig-models-with(extractor, input=, output=, iterations=1, iteration_field=iteration, file_fields=, timeout=0) {
        output="${output:-extract-kconfig-models-with-$extractor}"
        iterate \
            --iterations "$iterations" \
            --iteration-field "$iteration_field" \
            --file-fields "$file_fields" \
            --image "$extractor" \
            --input "$input" \
            --output "$output" \
            --resumable y \
            --command "extract-kconfig-models-with-$extractor" \
            --timeout "$timeout"
    }

    # extracts kconfig models with kconfigreader and kclause
    extract-kconfig-models(input=, output=extract-kconfig-models, iterations=1, iteration_field=iteration, file_fields=, timeout=0) {
        extract-kconfig-models-with \
            --extractor kconfigreader \
            --input "$input" \
            --output extract-kconfig-models-with-kconfigreader \
            --iterations "$iterations" \
            --iteration-field "$iteration_field" \
            --file-fields "$file_fields" \
            --timeout "$timeout"
        extract-kconfig-models-with \
            --extractor kclause \
            --input "$input" \
            --output extract-kconfig-models-with-kclause \
            --iterations "$iterations" \
            --iteration-field "$iteration_field" \
            --file-fields "$file_fields" \
            --timeout "$timeout"
        # extract-kconfig-models-with \
        # --extractor configfix \
        # --output configfix \
        # --iterations "$iterations" \
        # --iteration-field "$iteration_field" \
        # --file-fields "$file_fields" \
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
            --inputs extract-kconfig-models-with-kconfigreader extract-kconfig-models-with-kclause
            # --inputs kconfigreader kclause configfix
    }

    # transforms model files with FeatJAR
    transform-model-with-featjar(transformer, output_extension, input=extract-kconfig-models, command=transform-with-featjar, timeout=0, jobs=1, iterations=1, iteration_field=iteration, file_fields=) {
        # shellcheck disable=SC2128
        iterate \
            --iterations "$iterations" \
            --iteration-field "$iteration_field" \
            --file-fields "$file_fields" \
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
    transform-model-to-dimacs-with-featjar(transformer, input=extract-kconfig-models, timeout=0, jobs=1, iterations=1, iteration_field=iteration, file_fields=) {
        transform-model-with-featjar \
            --command transform-to-dimacs-with-featjar \
            --output-extension dimacs \
            --input "$input" \
            --transformer "$transformer" \
            --timeout "$timeout" \
            --jobs "$jobs" \
            --iterations "$iterations" \
            --iteration-field "$iteration_field" \
            --file-fields "$file_fields"
    }

    # transforms model files to DIMACS
    transform-model-to-dimacs(input=extract-kconfig-models, output=transform-model-to-dimacs, timeout=0, jobs=1) {
        # distributive tranformation
        transform-model-to-dimacs-with-featjar \
            --transformer transform-model-to-dimacs-with-featureide \
            --input "$input" \
            --timeout "$timeout" \
            --jobs "$jobs"
        transform-model-to-dimacs-with-featjar \
            --transformer transform-model-to-dimacs-with-featjar \
            --input "$input" \
            --timeout "$timeout" \
            --jobs "$jobs"
        
        # intermediate formats for CNF transformation
        transform-model-with-featjar \
            --transformer transform-model-to-model-with-featureide \
            --output-extension featureide.model \
            --input "$input" \
            --timeout "$timeout" \
            --jobs "$jobs"
        transform-model-with-featjar \
            --transformer transform-model-to-smt-with-z3 \
            --output-extension smt \
            --input "$input" \
            --timeout "$timeout" \
            --jobs "$jobs"

        # Plaisted-Greenbaum CNF tranformation
        # todo: extract primitives and reuse in experiments
        run \
            --image kconfigreader \
            --input transform-model-to-model-with-featureide \
            --output transform-model-to-dimacs-with-kconfigreader \
            --resumable y \
            --command transform-model-to-dimacs-with-kconfigreader \
            --input-extension featureide.model \
            --timeout "$timeout" \
            --jobs "$jobs"
        join-into transform-model-to-model-with-featureide transform-model-to-dimacs-with-kconfigreader

        # Tseitin CNF tranformation
        run \
            --image z3 \
            --input transform-model-to-smt-with-z3 \
            --output transform-smt-to-dimacs-with-z3 \
            --resumable y \
            --command transform-smt-to-dimacs-with-z3 \
            --timeout "$timeout" \
            --jobs "$jobs"
        join-into transform-model-to-smt-with-z3 transform-smt-to-dimacs-with-z3

        aggregate \
            --output "$output" \
            --directory-field dimacs_transformer \
            --file-fields dimacs_file \
            --inputs transform-model-to-dimacs-with-featureide transform-model-to-dimacs-with-featjar transform-model-to-dimacs-with-kconfigreader transform-smt-to-dimacs-with-z3
    }

    # visualize community structure of DIMACS files as a JPEG file
    draw-community-structure-with-satgraf(input=transform-model-to-dimacs, output=draw-community-structure-with-satgraf, timeout=0, jobs=1) {
        run \
            --image satgraf \
            --input "$input" \
            --output "$output" \
            --resumable y \
            --command draw-community-structure-with-satgraf \
            --timeout "$timeout" \
            --jobs "$jobs"
    }

    # compute DIMACS files with explicit backbone using kissat
    transform-dimacs-to-backbone-dimacs-with-kissat(input=transform-model-to-dimacs, output=transform-dimacs-to-backbone-dimacs, timeout=0, jobs=1) {
        run \
            --image solver \
            --input "$input" \
            --output "$output" \
            --resumable y \
            --command transform-dimacs-to-backbone-dimacs-with-kissat \
            --timeout "$timeout" \
            --jobs "$jobs"
    }

    # compute DIMACS files with explicit backbone using cadiback
    transform-dimacs-to-backbone-dimacs-with-cadiback(input=transform-model-to-dimacs, output=transform-dimacs-to-backbone-dimacs, timeout=0, jobs=1) {
        run \
            --image cadiback \
            --input "$input" \
            --output "$output" \
            --resumable y \
            --command transform-dimacs-to-backbone-dimacs-with-cadiback \
            --timeout "$timeout" \
            --jobs "$jobs"
    }

    # compute unconstrained features that are not mentioned in a DIMACS file
    compute-unconstrained-features(input=extract-kconfig-models, output=compute-unconstrained-features, timeout=0, jobs=1) {
        run \
            --input "$input" \
            --output "$output" \
            --resumable y \
            --command compute-unconstrained-features \
            --timeout "$timeout" \
            --jobs "$jobs"
    }

    # compute features in the backbone of DIMACS files
    compute-backbone-features(input=transform-dimacs-to-backbone-dimacs, output=compute-backbone-features, timeout=0, jobs=1) {
        run \
            --input "$input" \
            --output "$output" \
            --resumable y \
            --command compute-backbone-features \
            --timeout "$timeout" \
            --jobs "$jobs"
    }

    # solve DIMACS files
    solve(kind, input=transform-model-to-dimacs, input_extension=dimacs, timeout=0, jobs=1, attempts=, attempt_grouper=, iterations=1, iteration_field=iteration, file_fields=, solver_specs...) {
        local stages=()
        for solver_spec in "${solver_specs[@]}"; do
            local solver stage image parser
            solver=$(echo "$solver_spec" | cut -d, -f1)
            stage=${solver/$DOCKER_INPUT_DIRECTORY\/$SAT_HERITAGE_INPUT_KEY/}
            stage=${stage/run.sh/}
            stage=$(echo "$stage" | sed -E 's#[/_.+ ]+#-#g; s/^-+//; s/-+$//')
            stage=solve-${stage,,}
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
                --attempt-grouper "$attempt_grouper"
        done
        aggregate --output "solve-$kind" --inputs "${stages[@]}"
    }

    # solve DIMACS files for satisfiability
    # many solvers are available, which are listed below, but only few are enabled by default
    solve-sat(input=transform-model-to-dimacs, timeout=0, jobs=1, attempts=, attempt_grouper=, iterations=1, iteration_field=iteration, file_fields=) {
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
            --iterations "$iterations" --iteration_field "$iteration_field" --file_fields "$file_fields" \
            --solver_specs "${solver_specs[@]}"
    }

    # solve DIMACS files for model count
    # many solvers are available, which are listed below, but only few are enabled by default
    solve-sharp-sat(input=transform-model-to-dimacs, timeout=0, jobs=1, attempts=, attempt_grouper=) {
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
            --attempts "$attempts" --attempt-grouper "$attempt_grouper" --solver_specs "${solver_specs[@]}"
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