#!/bin/bash
# The following line uses curl to reproducibly install and run the specified revision of torte.
# Alternatively, torte can be installed manually (see https://github.com/ekuiter/torte).
# In that case, make sure to check out the correct revision manually and run ./torte.sh <this-file>.
TORTE_REVISION=main; [[ $TOOL != torte ]] && builtin source /dev/stdin <<<"$(curl -fsSL https://raw.githubusercontent.com/ekuiter/torte/$TORTE_REVISION/torte.sh)" "$@"

TIMEOUT=3600
# parameters for computing model count
SOLVE_TIMEOUT=3600 # timeout in seconds
SOLVE_JOBS=4 # number of parallel jobs to run, should not exceed number of attempts
SOLVE_ATTEMPTS=4 # how many successive timeouts are allowed before giving up and moving on

experiment-subjects() {
    #add-testsystem-kconfig v0.0
    add-toybox-kconfig-history 
    add-axtls-kconfig-history
    add-embtoolkit-kconfig-history
    add-fiasco-kconfig 58aa50a8aae2e9396f1c8d1d0aa53f2da20262ed
    add-freetz-ng-kconfig 5c5a4d1d87ab8c9c6f121a13a8fc4f44c79700af
    add-busybox-kconfig-history 
    add-linux-kconfig-history --from v4.18 --to v5.6 --architecture x86
    add-uclibc-ng-kconfig-history
}

experiment-stages() {
    clone-systems
    read-toybox-configs
    read-axtls-configs
    read-embtoolkit-configs
    read-fiasco-configs
    read-freetz-ng-configs
    read-busybox-configs
    read-uclibc-ng-configs
    read-linux-configs
    extract-kconfig-models-with --extractor configfixextractor 
    #extract-kconfig-models-with --extractor kconfigreader
    #extract-kconfig-models-with --extractor kmax
    #extract-kconfig-models

    compute-unconstrained-features

    # transform
    transform-models-with-featjar --transformer model_to_smt_z3 --output-extension smt --jobs 2
    run \
        --stage dimacs \
        --image z3 \
        --input-directory model_to_smt_z3 \
        --command transform-into-dimacs-with-z3 \
        --jobs 2
    join-into model_to_smt_z3 dimacs
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
        --jobs "$SOLVE_JOBS" \
        --attempts "$SOLVE_ATTEMPTS" \
        --attempt-grouper "$(to-lambda linux-attempt-grouper)" \
        --solver_specs \
        model-counting-competition-2022/d4.sh,solver,model-counting-competition-2022 \
        model-counting-competition-2022/SharpSAT-td+Arjun/SharpSAT-td+Arjun.sh,solver,model-counting-competition-2022
    join-into backbone-dimacs solve_model-count
}
