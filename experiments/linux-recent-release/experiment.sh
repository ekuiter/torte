#!/bin/bash
# The following line uses curl to reproducibly install and run the specified revision of torte.
# Alternatively, torte can be installed manually (see https://github.com/ekuiter/torte).
# In that case, make sure to check out the correct revision manually and run ./torte.sh <this-file>.
TORTE_REVISION=main; [[ $TOOL != torte ]] && builtin source /dev/stdin <<<"$(curl -fsSL https://raw.githubusercontent.com/ekuiter/torte/$TORTE_REVISION/torte.sh)" "$@"

# This experiment extracts and transforms a single feature model from a recent revision of the Linux kernel.

experiment-systems() {
    add-linux-kconfig-history --from v6.17 --to v6.18 --architecture x86
}

experiment-stages() {
    # extract
    clone-systems
    extract-kconfig-models
    compute-unconstrained-features

    # transform
    transform-model-with-featjar --transformer transform-model-to-uvl-with-featureide --output-extension uvl --jobs 2
    transform-model-with-featjar --transformer transform-model-to-xml-with-featureide --output-extension xml --jobs 2
    transform-model-with-featjar --transformer transform-model-to-smt-with-z3 --output-extension smt --jobs 2
    run \
        --image z3 \
        --input transform-model-to-smt-with-z3 \
        --output transform-model-to-dimacs \
        --command transform-smt-to-dimacs-with-z3 \
        --jobs 2
    join-into transform-model-to-smt-with-z3 transform-model-to-dimacs
    join-into extract-kconfig-models transform-model-to-dimacs

    # solve
    transform-dimacs-to-backbone-dimacs-with --transformer cadiback --jobs 16
    join-into transform-model-to-dimacs transform-dimacs-to-backbone-dimacs
    compute-backbone-features --jobs 16
}