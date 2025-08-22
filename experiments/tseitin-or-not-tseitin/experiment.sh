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

experiment-test-systems() {
    # test with just BusyBox for speed
    add-busybox-kconfig-history --from 1_35_1 --to 1_35_1
}

experiment-stages() {
    # extract
    clone-systems
    read-statistics
    extract-kconfig-models \
        --iterations "$N" \
        --file-fields model_file
    join-into read-statistics extract-kconfig-models

    # transform
    transform-model-to-dimacs-with-featjar \
        --transformer transform-model-to-dimacs-with-featureide
    transform-model-with-featjar \
        --transformer transform-model-to-smt-with-z3 \
        --output-extension smt \
        --jobs 16
    transform-model-with-featjar \
        --transformer transform-model-to-model-with-featureide \
        --output-extension featureide.model \
        --jobs 16
    run \
        --image kconfigreader \
        --input transform-model-to-model-with-featureide \
        --output transform-model-to-dimacs-with-kconfigreader \
        --command transform-model-to-dimacs-with-kconfigreader \
        --input-extension featureide.model
    join-into transform-model-to-model-with-featureide transform-model-to-dimacs-with-kconfigreader
    run \
        --image z3 \
        --input transform-model-to-smt-with-z3 \
        --output transform-smt-to-dimacs-with-z3 \
        --command transform-smt-to-dimacs-with-z3
    join-into transform-model-to-smt-with-z3 transform-smt-to-dimacs-with-z3
    aggregate \
        --output transform-model-to-dimacs \
        --directory-field dimacs_transformer \
        --file-fields dimacs_file \
        --inputs transform-model-to-dimacs-with-featureide transform-model-to-dimacs-with-kconfigreader transform-smt-to-dimacs-with-z3
    join-into extract-kconfig-models transform-model-to-dimacs

    # analyze
    transform-dimacs-to-backbone-dimacs-with-cadiback
    join-into transform-model-to-dimacs transform-dimacs-to-backbone-dimacs
    compute-backbone-features --jobs 16

    solve \
        --input transform-dimacs-to-backbone-dimacs \
        --input-extension backbone.dimacs \
        --kind sharp-sat \
        --timeout "$SOLVE_TIMEOUT" \
        --solver_specs \
        sat-competition/02-zchaff,solver,sat \
        sat-competition/03-Forklift,solver,sat \
        sat-competition/04-zchaff,solver,sat \
        sat-competition/05-SatELiteGTI.sh,solver,sat \
        sat-competition/06-MiniSat,solver,sat \
        sat-competition/07-RSat.sh,solver,sat \
        sat-competition/09-precosat,solver,sat \
        sat-competition/10-CryptoMiniSat,solver,sat \
        sat-competition/11-glucose.sh,solver,sat \
        sat-competition/12-glucose.sh,solver,sat \
        sat-competition/13-lingeling-aqw,solver,sat \
        sat-competition/14-lingeling-ayv,solver,sat \
        sat-competition/16-MapleCOMSPS_DRUP,solver,sat \
        sat-competition/17-Maple_LCM_Dist,solver,sat \
        sat-competition/18-MapleLCMDistChronoBT,solver,sat \
        sat-competition/19-MapleLCMDiscChronoBT-DL-v3,solver,sat \
        sat-competition/20-Kissat-sc2020-sat,solver,sat \
        sat-competition/21-Kissat_MAB,solver,sat \
        emse-2023/countAntom,solver,sharp-sat \
        emse-2023/d4,solver,sharp-sat \
        emse-2023/dSharp,solver,sharp-sat \
        emse-2023/ganak,solver,sharp-sat \
        emse-2023/sharpSAT,solver,sharp-sat
   join-into transform-dimacs-to-backbone-dimacs solve-sharp-sat
}