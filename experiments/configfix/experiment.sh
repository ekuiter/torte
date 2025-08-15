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

experiment-systems() {
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
    extract-kconfig-models-with --extractor configfix 
    #extract-kconfig-models-with --extractor kconfigreader
    #extract-kconfig-models-with --extractor kclause
    #extract-kconfig-models

    compute-unconstrained-features

    # transform
    transform-model-with-featjar --transformer transform-model-to-smt-with-z3 --output-extension smt --jobs 2
    run \
        --image z3 \
        --input transform-model-to-smt-with-z3 \
        --output transform-model-to-dimacs \
        --command transform-smt-to-dimacs-with-z3 \
        --jobs 2
    join-into transform-model-to-smt-with-z3 transform-model-to-dimacs
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
        --jobs "$SOLVE_JOBS" \
        --attempts "$SOLVE_ATTEMPTS" \
        --attempt-grouper "$(to-lambda linux-attempt-grouper)" \
        --solver_specs \
        mcc-2022/d4.sh,solver,sharp-sat-mcc22 \
        mcc-2022/SharpSAT-td+Arjun/SharpSAT-td+Arjun.sh,solver,sharp-sat-mcc22
    join-into transform-dimacs-to-backbone-dimacs solve-sharp-sat
}
