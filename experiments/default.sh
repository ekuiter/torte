#!/bin/bash
# The following line uses curl to reproducibly install and run the specified revision of torte.
# Alternatively, torte can be installed manually (see https://github.com/ekuiter/torte).
# In that case, make sure to check out the correct revision manually and run torte.sh <this-file>.
TORTE_REVISION=f0f2fe7; [[ -z $DOCKER_PREFIX ]] && builtin source <(curl -fsSL https://raw.githubusercontent.com/ekuiter/torte/$TORTE_REVISION/torte.sh) "$@"

experiment-subjects() {
    add-busybox-kconfig-history --from 1_36_0 --to 1_37_0
}

experiment-stages() {
    run-clone-systems
    run-tag-linux-revisions
    run-read-statistics
    run-extract-kconfig-models
    run-transform-models-with-featjar --transformer model_to_xml_featureide --output-extension xml
    run-transform-models-with-featjar --transformer model_to_uvl_featureide --output-extension uvl
    run-transform-models-into-dimacs
    join-into kconfig dimacs

    run \
        --stage community-structure \
        --image satgraf \
        --input-directory dimacs \
        --command transform-with-satgraf

    local solver_specs=(
        z3,z3,satisfiable
        emse-2023/countAntom,solver,model-count
        emse-2023/d4,solver,model-count
        emse-2023/dsharp,solver,model-count
        emse-2023/ganak,solver,model-count
        emse-2023/sharpSAT,solver,model-count
        sat-competition/02-zchaff,solver,satisfiable
        sat-competition/03-Forklift,solver,satisfiable
        sat-competition/04-zchaff,solver,satisfiable
        sat-competition/05-SatELiteGTI.sh,solver,satisfiable
        sat-competition/06-MiniSat,solver,satisfiable
        sat-competition/07-RSat.sh,solver,satisfiable
        sat-competition/09-precosat,solver,satisfiable
        sat-competition/10-CryptoMiniSat,solver,satisfiable
        sat-competition/11-glucose.sh,solver,satisfiable
        sat-competition/11-SatELite,solver,satisfiable
        sat-competition/12-glucose.sh,solver,satisfiable
        sat-competition/12-SatELite,solver,satisfiable
        sat-competition/13-lingeling-aqw,solver,satisfiable
        sat-competition/14-lingeling-ayv,solver,satisfiable
        sat-competition/16-MapleCOMSPS_DRUP,solver,satisfiable
        sat-competition/17-Maple_LCM_Dist,solver,satisfiable
        sat-competition/18-MapleLCMDistChronoBT,solver,satisfiable
        sat-competition/19-MapleLCMDiscChronoBT-DL-v3,solver,satisfiable
        sat-competition/20-Kissat-sc2020-sat,solver,satisfiable
        sat-competition/21-Kissat_MAB,solver,satisfiable
        other/sat4j.sh,solver,satisfiable
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