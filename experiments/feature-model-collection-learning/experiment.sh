#!/bin/bash
# The following line uses curl to reproducibly install and run the specified revision of torte.
# Alternatively, torte can be installed manually (see https://github.com/ekuiter/torte).
# In that case, make sure to check out the correct revision manually and run ./torte.sh <this-file>.
TORTE_REVISION=main; [[ $TOOL != torte ]] && builtin source /dev/stdin <<<"$(curl -fsSL https://raw.githubusercontent.com/ekuiter/torte/$TORTE_REVISION/torte.sh)" "$@"

# Learning from feature-model histories

TIMEOUT=300 # timeout for extraction and transformation in seconds

experiment-systems() {
    add-axtls-kconfig-history --from release-1.0.0 --to release-2.0.1
    add-embtoolkit-kconfig-history --from embtoolkit-1.0.0 --to embtoolkit-1.8.0
    add-uclibc-ng-kconfig-history --from v1.0.2 --to v1.0.48
}

experiment-stages() {
    clone-systems
    read-statistics skip-sloc
    extract-kconfig-models-with --extractor kclause
    join-into read-statistics extract-kconfig-models-with-kclause
    transform-model-to-dimacs --timeout "$TIMEOUT"
}