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
    extract-kconfig-models --with-kconfigreader y --with-kclause y --with-configfix y
    compute-unconstrained-features

    # transform
    transform-to-xml --timeout "$TIMEOUT" --jobs 2
    transform-to-uvl --timeout "$TIMEOUT" --jobs 2
    transform-to-dimacs --with-z3 y --jobs 2
    join-into extract-kconfig-models transform-to-dimacs

    # solve
    transform-dimacs-to-backbone-dimacs-with --transformer cadiback --jobs 16
    join-into transform-to-dimacs transform-dimacs-to-backbone-dimacs
    compute-backbone-features --jobs 16
}