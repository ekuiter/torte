#!/bin/bash
# The following line uses curl to reproducibly install and run the specified revision of torte.
# Alternatively, torte can be installed manually (see https://github.com/ekuiter/torte).
# In that case, make sure to check out the correct revision manually and run ./torte.sh <this-file>.
TORTE_REVISION=main; [[ $TOOL != torte ]] && builtin source /dev/stdin <<<"$(curl -fsSL https://raw.githubusercontent.com/ekuiter/torte/$TORTE_REVISION/torte.sh)" "$@"

# This file reproduces the evaluation for the ASE'22 paper "Tseitin or not Tseitin? The Impact of CNF Transformations on Feature-Model Analyses".
# The original evaluation script is available at https://github.com/ekuiter/tseitin-or-not-tseitin/blob/main/input/extract_ase22.sh.

N=3 # number of iterations
TRANSFORM_TIMEOUT=180 # timeout for CNF transformation in seconds
SOLVE_TIMEOUT=1200 # timeout for model counting in seconds
SAMPLE_SEED=20261002 # fixed seed for reproducible random feature samples
NUM_FEATURES=3 # number of randomly sampled core/dead/feature-cardinality queries

add-payload-file evaluation.ipynb

download-hierarchy-models() {
    local hierarchy_models=(
        automotive,2_1.xml
        automotive,2_2.xml
        automotive,2_3.xml
        automotive,2_4.xml
        axtls,unknown.xml
        busybox,1.18.0.xml
        cdl-am31_sim,unknown.xml
        cdl-ea2468,unknown.xml
        cdl-lpcmt,unknown.xml
        embtoolkit,unknown.xml
        linux,2.6.33.3.xml
        uclibc,unknown.xml
        uclinux-base,unknown.xml
        uclinux-distribution,unknown.xml
    )
    local local_file remote_file
    hierarchy_model_files=()
    for remote_file in "${hierarchy_models[@]}"; do
        local_file=${remote_file//,/-}
        download-payload-file "hierarchies/$local_file" \
            "https://raw.githubusercontent.com/ekuiter/tseitin-or-not-tseitin/main/input/hierarchies/${remote_file//,/%2C}"
        hierarchy_model_files+=("hierarchies/$local_file")
    done
}

download-hierarchy-models

sat_solver_specs=(
    sat-competition/02-zchaff,solver,sat
    sat-competition/03-Forklift,solver,sat
    sat-competition/04-zchaff,solver,sat
    sat-competition/05-SatELiteGTI.sh,solver,sat
    sat-competition/06-MiniSat,solver,sat
    sat-competition/07-RSat.sh,solver,sat
    sat-competition/09-precosat,solver,sat
    sat-competition/10-CryptoMiniSat,solver,sat
    sat-competition/11-glucose.sh,solver,sat
    sat-competition/12-glucose.sh,solver,sat
    sat-competition/13-lingeling-aqw,solver,sat
    sat-competition/14-lingeling-ayv,solver,sat
    sat-competition/16-MapleCOMSPS_DRUP,solver,sat
    sat-competition/17-Maple_LCM_Dist,solver,sat
    sat-competition/18-MapleLCMDistChronoBT,solver,sat
    sat-competition/19-MapleLCMDiscChronoBT-DL-v3,solver,sat
    sat-competition/20-Kissat-sc2020-sat,solver,sat
    sat-competition/21-Kissat_MAB,solver,sat
)

sharp_sat_solver_specs=(
    emse-2023/countAntom,solver,sharp-sat
    emse-2023/d4,solver,sharp-sat
    emse-2023/dSharp,solver,sharp-sat
    emse-2023/ganak,solver,sharp-sat
    emse-2023/sharpSAT,solver,sharp-sat
)

experiment-systems() {
    add-linux-kconfig --revision v4.18 --architecture x86
    add-axtls-kconfig release-2.0.0
    add-buildroot-kconfig 2021.11.2
    add-busybox-kconfig 1_35_0
    add-embtoolkit-kconfig embtoolkit-1.8.0
    add-l4re-kconfig 58aa50a8aae2e9396f1c8d1d0aa53f2da20262ed
    add-freetz-ng-kconfig 5c5a4d1d87ab8c9c6f121a13a8fc4f44c79700af
    add-uclibc-ng-kconfig v1.0.40
    for file in "${hierarchy_model_files[@]}"; do
        add-model-payload-file "$file"
    done
}

experiment-stages() {
    # extract
    clone-systems
    read-statistics
    extract-kconfig-models --with-kconfigreader "$N" --with-kclause "$N"
    join-into read-statistics extract-kconfig-models

    # transform
    transform-to-dimacs \
        --with-featureide y \
        --with-kconfigreader y \
        --with-z3 y \
        --timeout "$TRANSFORM_TIMEOUT"
    join-into extract-kconfig-models transform-to-dimacs

    # solve
    compute-constrained-features
    compute-random-sample \
        --input compute-constrained-features \
        --output feature-sample \
        --extension constrained.features \
        --size "$NUM_FEATURES" \
        --seed "$SAMPLE_SEED"

    for query_spec in \
        "void;" \
        "core;core" \
        "dead;dead"; do
        query_name=$(echo "$query_spec" | cut -d';' -f1)
        query_iterator=$(echo "$query_spec" | cut -d';' -f2)
        solve_args=(
            --kind sat \
            --query "$query_name" \
            --timeout "$SOLVE_TIMEOUT"
        )
        if [[ -n $query_iterator ]]; then
            solve_args+=(
                --input "$(mount-dimacs-input),$(mount-query-sample feature-sample)"
                --query-iterator "$(to-lambda query-$query_iterator constrained.features)"
            )
        fi
        solve_args+=(--solver_specs "${sat_solver_specs[@]}")
        solve "${solve_args[@]}"
        sat_solve_stages+=("solve-$query_name-sat")
    done
    aggregate --output solve-sat --inputs "${sat_solve_stages[@]}"

    for query_spec in \
        "feature-model-cardinality;" \
        "feature-cardinality;dead"; do
        query_name=$(echo "$query_spec" | cut -d';' -f1)
        query_iterator=$(echo "$query_spec" | cut -d';' -f2)
        solve_args=(
            --kind sharp-sat \
            --query "$query_name" \
            --timeout "$SOLVE_TIMEOUT"
        )
        if [[ -n $query_iterator ]]; then
            solve_args+=(
                --input "$(mount-dimacs-input),$(mount-query-sample feature-sample)"
                --query-iterator "$(to-lambda query-$query_iterator constrained.features)"
            )
        fi
        solve_args+=(--solver_specs "${sharp_sat_solver_specs[@]}")
        solve "${solve_args[@]}"
        sharp_sat_solve_stages+=("solve-$query_name-sharp-sat")
    done
    aggregate --output solve-sharp-sat --inputs "${sharp_sat_solve_stages[@]}"

    run-jupyter-notebook \
        --input transform=transform-to-dimacs,sat=solve-sat,sharp=solve-sharp-sat \
        --payload-file evaluation.ipynb
}
