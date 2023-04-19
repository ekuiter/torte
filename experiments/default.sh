#!/bin/bash
# The following line uses curl to reproducibly install and run the specified revision of torte.
# Alternatively, torte can be installed manually (see https://github.com/ekuiter/torte).
# In that case, make sure to check out the correct revision manually and run torte.sh <this-file>.
TORTE_REVISION=main; [[ -z $DOCKER_PREFIX ]] && builtin source <(curl -fsSL https://raw.githubusercontent.com/ekuiter/torte/$TORTE_REVISION/torte.sh) "$@"

experiment-subjects() {
    add-system --system busybox --url https://github.com/mirror/busybox
    
    add-kconfig \
        --system busybox \
        --revision 1_18_0 \
        --kconfig-file Config.in \
        --kconfig-binding-files scripts/kconfig/*.o
}

experiment-stages() {
    extract-with(extractor) {
        run \
            --stage "$extractor" \
            --image "$extractor" \
            --command "extract-with-$extractor"
    }

    transform-with-featjar(transformer, output_extension, command=transform-with-featjar) {
        run \
            --stage "$transformer" \
            --image featjar \
            --input-directory kconfig \
            --command "$command" \
            --input-extension model \
            --output-extension "$output_extension" \
            --transformer "$transformer"
    }

    transform-into-dimacs-with-featjar(transformer) {
        transform-with-featjar --command transform-into-dimacs-with-featjar --output-extension dimacs --transformer "$transformer"
    }

    run --stage clone-systems
    run --stage tag-linux-revisions
    run --stage read-statistics
    extract-with --extractor kconfigreader
    extract-with --extractor kmax
    aggregate \
        --stage kconfig \
        --stage-field extractor \
        --file-fields binding-file,model-file \
        --stages kconfigreader kmax
    
    transform-with-featjar --transformer model_to_xml_featureide --output-extension xml
    transform-with-featjar --transformer model_to_uvl_featureide --output-extension uvl
    transform-into-dimacs-with-featjar --transformer model_to_dimacs_featureide
    transform-into-dimacs-with-featjar --transformer model_to_dimacs_featjar
    transform-with-featjar --transformer model_to_model_featureide --output-extension featureide.model
    transform-with-featjar --transformer model_to_smt_z3 --output-extension smt

    run \
        --stage model_to_dimacs_kconfigreader \
        --image kconfigreader \
        --input-directory model_to_model_featureide \
        --command transform-into-dimacs-with-kconfigreader \
        --input-extension featureide.model
    join-into model_to_model_featureide model_to_dimacs_kconfigreader

    run \
        --stage smt_to_dimacs_z3 \
        --image z3 \
        --input-directory model_to_smt_z3 \
        --command transform-into-dimacs-with-z3
    join-into model_to_smt_z3 smt_to_dimacs_z3

    aggregate \
        --stage dimacs \
        --directory-field dimacs-transformer \
        --file-fields dimacs-file \
        --stages model_to_dimacs_featureide model_to_dimacs_kconfigreader smt_to_dimacs_z3
    join-into kconfig dimacs

    run \
        --stage community-structure \
        --image satgraf \
        --input-directory dimacs \
        --command transform-with-satgraf
    join-into dimacs community-structure
    join-into read-statistics community-structure

    force

    local solver_specs=(
        z3,z3,satisfiable
        ase-2022/countAntom,solver,model-count # todo: currently only returns NA
        ase-2022/d4,solver,model-count
        ase-2022/dsharp,solver,model-count
        ase-2022/ganak,solver,model-count
        ase-2022/sharpSAT,solver,model-count
        sat-competition-winners/02-zchaff,solver,satisfiable
        sat-competition-winners/03-Forklift,solver,satisfiable
        sat-competition-winners/04-zchaff,solver,satisfiable
        sat-competition-winners/05-SatELiteGTI.sh,solver,satisfiable
        sat-competition-winners/06-MiniSat,solver,satisfiable
        sat-competition-winners/07-RSat.sh,solver,satisfiable
        sat-competition-winners/09-precosat,solver,satisfiable
        sat-competition-winners/10-CryptoMiniSat,solver,satisfiable
        sat-competition-winners/11-glucose.sh,solver,satisfiable
        sat-competition-winners/11-SatELite,solver,satisfiable
        sat-competition-winners/12-glucose.sh,solver,satisfiable
        sat-competition-winners/12-SatELite,solver,satisfiable
        sat-competition-winners/13-lingeling-aqw,solver,satisfiable
        sat-competition-winners/14-lingeling-ayv,solver,satisfiable
        sat-competition-winners/16-MapleCOMSPS_DRUP,solver,satisfiable
        sat-competition-winners/17-Maple_LCM_Dist,solver,satisfiable
        sat-competition-winners/18-MapleLCMDistChronoBT,solver,satisfiable
        sat-competition-winners/19-MapleLCMDiscChronoBT-DL-v3,solver,satisfiable
        sat-competition-winners/20-Kissat-sc2020-sat,solver,satisfiable
        sat-competition-winners/21-Kissat_MAB,solver,satisfiable
        sat4j/sat4j.sh,solver,satisfiable
    )
    local satisfiable_stages=()
    local model_count_stages=()
    for solver_spec in "${solver_specs[@]}"; do
        local solver stage image parser
        solver=$(echo "$solver_spec" | cut -d, -f1)
        stage=${solver//\//_}
        stage=solve_${stage,,}
        image=$(echo "$solver_spec" | cut -d, -f2)
        parser=$(echo "$solver_spec" | cut -d, -f3)
        if [[ $parser == satisfiable ]]; then
            satisfiable_stages+=("$stage")
        else
            model_count_stages+=("$stage")
        fi
        run \
            --stage "$stage" \
            --image "$image" \
            --input-directory dimacs \
            --command solve --solver "$solver" --parser "$parser" --timeout 10
    done
    aggregate --stage solve_satisfiable --stages "${satisfiable_stages[@]}"
    aggregate --stage solve_model_count --stages "${model_count_stages[@]}"
}