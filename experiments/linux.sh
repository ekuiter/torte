#!/bin/bash
# The following line uses curl to reproducibly install and run the specified revision of torte.
# Alternatively, torte can be installed manually (see https://github.com/ekuiter/torte).
# In that case, make sure to check out the correct revision manually and run torte.sh <this-file>.
TORTE_REVISION=main; [[ -z $DOCKER_PREFIX ]] && builtin source <(curl -fsSL https://raw.githubusercontent.com/ekuiter/torte/$TORTE_REVISION/torte.sh) "$@"

experiment-subjects() {
    #add-linux-kconfig-history --from v2.5.45 --to v6.0
    add-linux-kconfig-history --from v2.5.45 --to v3.0
    #add-linux-kconfig-history --from v6.3 --to v6.4
}

experiment-stages() {
    force
    run --stage clone-systems
    run --stage tag-linux-revisions
    #run --stage read-linux-names
    #run --stage read-statistics
    #join-into read-linux-names read-statistics

    #plot --stage read-statistics --type scatter --fields committer_date_unix,source_lines_of_code

    extract-with(extractor) {
        run \
            --stage "$extractor" \
            --image "$extractor" \
            --command "extract-with-$extractor"
    }
    
    #extract-with kconfigreader
    extract-with kmax
    
    aggregate \
        --stage model \
        --stage-field extractor \
        --file-fields binding-file,model-file \
        --stages kmax #kconfigreader
    #join-into read-statistics model

    transform-with-featjar(transformer, output_extension, command=transform-with-featjar) {
        run \
            --stage "$transformer" \
            --image featjar \
            --input-directory model \
            --command "$command" \
            --input-extension model \
            --output-extension "$output_extension" \
            --transformer "$transformer"
    }

    #transform-with-featjar --transformer model_to_xml_featureide --output-extension xml
    #transform-with-featjar --transformer model_to_uvl_featureide --output-extension uvl
    transform-with-featjar --transformer model_to_smt_z3 --output-extension smt

    run \
        --stage dimacs \
        --image z3 \
        --input-directory model_to_smt_z3 \
        --command transform-into-dimacs-with-z3
    join-into model_to_smt_z3 dimacs
    join-into model dimacs

    local solver_specs=(
        other/d4.sh,solver,model-count
    )
    local model_count_stages=()
    for solver_spec in "${solver_specs[@]}"; do
        local solver stage image parser
        solver=$(echo "$solver_spec" | cut -d, -f1)
        stage=${solver//\//_}
        stage=solve_${stage,,}
        image=$(echo "$solver_spec" | cut -d, -f2)
        parser=$(echo "$solver_spec" | cut -d, -f3)
        model_count_stages+=("$stage")
        run \
            --stage "$stage" \
            --image "$image" \
            --input-directory dimacs \
            --command solve --solver "$solver" --parser "$parser" --timeout 1800
    done
    aggregate --stage solve_model_count --stages "${model_count_stages[@]}"
    join-into dimacs solve_model_count
}