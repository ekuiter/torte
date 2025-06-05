#!/bin/bash
# The following line uses curl to reproducibly install and run the specified revision of torte.
# Alternatively, torte can be installed manually (see https://github.com/ekuiter/torte).
# In that case, make sure to check out the correct revision manually and run ./torte.sh <this-file>.
TORTE_REVISION=main; [[ $TOOL != torte ]] && builtin source /dev/stdin <<<"$(curl -fsSL https://raw.githubusercontent.com/ekuiter/torte/$TORTE_REVISION/torte.sh)" "$@"

# This file reproduces the evaluation for the ASE'22 paper "Tseitin or not Tseitin? The Impact of CNF Transformations on Feature-Model Analyses".
# The original evaluation script is available at https://github.com/ekuiter/tseitin-or-not-tseitin/blob/main/input/extract_ase22.sh.
# Here, we make a few small changes to the original evaluation:
# - The core and dead analysis has been implemented as a backbone-DIMACS transformation that determines all core and dead features.
# - The stage for counting feature cardinalities is not implemented yet.
# - The feature-model hierarchies are not included yet, only KConfig models are evaluated.
# - The subsequent R analysis script available at https://github.com/ekuiter/tseitin-or-not-tseitin/blob/main/ase22_evaluation.R is not yet adapted.

N=3 # number of iterations
TRANSFORM_TIMEOUT=180 # timeout for CNF transformation in seconds
SOLVE_TIMEOUT=1200 # timeout for model counting in seconds

experiment-systems() {
    add-linux-kconfig-history --from v4.18 --to v4.19 --architecture x86
    add-axtls-kconfig-history --from release-2.0.0 --to release-2.0.1
    add-buildroot-kconfig-history --from 2021.11.2 --to 2021.11.3
    add-busybox-kconfig-history --from 1_35_0 --to 1_35_1
    add-embtoolkit-kconfig-history --from embtoolkit-1.8.0 --to embtoolkit-1.8.1
    add-fiasco-kconfig 58aa50a8aae2e9396f1c8d1d0aa53f2da20262ed
    add-freetz-ng-kconfig 5c5a4d1d87ab8c9c6f121a13a8fc4f44c79700af
    add-uclibc-ng-kconfig-history --from v1.0.40 --to v1.0.41
}

experiment-stages() {
    # extract
    clone-systems
    read-statistics
    extract-kconfig-models \
        --iterations "$N" \
        --file-fields model-file
    join-into read-statistics kconfig

    # transform
    transform-models-into-dimacs-with-featjar \
        --transformer model_to_dimacs_featureide
    transform-models-with-featjar \
        --transformer model_to_smt_z3 \
        --output-extension smt \
        --jobs 16
    transform-models-with-featjar \
        --transformer model_to_model_featureide \
        --output-extension featureide.model \
        --jobs 16
    run \
        --stage model_to_dimacs_kconfigreader \
        --image kconfigreader \
        --input model_to_model_featureide \
        --command transform-into-dimacs-with-kconfigreader \
        --input-extension featureide.model
    join-into model_to_model_featureide model_to_dimacs_kconfigreader
    run \
        --stage smt_to_dimacs_z3 \
        --image z3 \
        --input model_to_smt_z3 \
        --command transform-into-dimacs-with-z3
    join-into model_to_smt_z3 smt_to_dimacs_z3
    aggregate \
        --stage dimacs \
        --directory-field dimacs-transformer \
        --file-fields dimacs-file \
        --stages model_to_dimacs_featureide model_to_dimacs_kconfigreader smt_to_dimacs_z3
    join-into kconfig dimacs

    # analyze
    compute-backbone-dimacs-with-cadiback
    join-into dimacs backbone-dimacs
    compute-backbone-features --jobs 16

    solve \
        --input-stage backbone-dimacs \
        --input-extension backbone.dimacs \
        --kind model-count \
        --timeout "$SOLVE_TIMEOUT" \
        --solver_specs \
        sat-competition/02-zchaff,solver,satisfiable \
        sat-competition/03-Forklift,solver,satisfiable \
        sat-competition/04-zchaff,solver,satisfiable \
        sat-competition/05-SatELiteGTI.sh,solver,satisfiable \
        sat-competition/06-MiniSat,solver,satisfiable \
        sat-competition/07-RSat.sh,solver,satisfiable \
        sat-competition/09-precosat,solver,satisfiable \
        sat-competition/10-CryptoMiniSat,solver,satisfiable \
        sat-competition/11-glucose.sh,solver,satisfiable \
        sat-competition/12-glucose.sh,solver,satisfiable \
        sat-competition/13-lingeling-aqw,solver,satisfiable \
        sat-competition/14-lingeling-ayv,solver,satisfiable \
        sat-competition/16-MapleCOMSPS_DRUP,solver,satisfiable \
        sat-competition/17-Maple_LCM_Dist,solver,satisfiable \
        sat-competition/18-MapleLCMDistChronoBT,solver,satisfiable \
        sat-competition/19-MapleLCMDiscChronoBT-DL-v3,solver,satisfiable \
        sat-competition/20-Kissat-sc2020-sat,solver,satisfiable \
        sat-competition/21-Kissat_MAB,solver,satisfiable \
        emse-2023/countAntom,solver,model-count \
        emse-2023/d4,solver,model-count \
        emse-2023/dSharp,solver,model-count \
        emse-2023/ganak,solver,model-count \
        emse-2023/sharpSAT,solver,model-count
   join-into backbone-dimacs solve_model-count
}