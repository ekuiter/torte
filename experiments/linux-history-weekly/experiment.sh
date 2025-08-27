#!/bin/bash
# The following line uses curl to reproducibly install and run the specified revision of torte.
# Alternatively, torte can be installed manually (see https://github.com/ekuiter/torte).
# In that case, make sure to check out the correct revision manually and run ./torte.sh <this-file>.
TORTE_REVISION=main; [[ $TOOL != torte ]] && builtin source /dev/stdin <<<"$(curl -fsSL https://raw.githubusercontent.com/ekuiter/torte/$TORTE_REVISION/torte.sh)" "$@"

# This experiment extracts a weekly history of feature models from the Linux kernel (x86).

experiment-systems() {
    add-linux-kconfig-sample --interval "$(interval weekly)"
}

# skip this experiment in CI because the Linux repository is too large for GitHub actions
experiment-test-systems(__NO_CI__) {
    add-linux-kconfig-sample --interval "$(interval per-decade)"
}

experiment-stages() {
    clone-systems
    read-statistics --option skip-sloc
    extract-kconfig-models-with --extractor kclause
    join-into read-statistics extract-kconfig-models-with-kclause
    collect-stage-files --input extract-kconfig-models-with-kclause --extension model
}