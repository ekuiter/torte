#!/bin/bash
# The following line uses curl to reproducibly install and run the specified revision of torte.
# Alternatively, torte can be installed manually (see https://github.com/ekuiter/torte).
# In that case, make sure to check out the correct revision manually and run ./torte.sh <this-file>.
TORTE_REVISION=main; [[ $TOOL != torte ]] && builtin source /dev/stdin <<<"$(curl -fsSL https://raw.githubusercontent.com/ekuiter/torte/$TORTE_REVISION/torte.sh)" "$@"

# This file extracts a history of feature-model formulas for Linux in SMT2 format.
# On the version stretch from 6.10 to 7.3, we have confirmed the semantics are accurate using differential tests.

experiment-systems() {
    add-linux-kconfig-tags --from v6.10 --to v7.3 --architecture x86 # "--architecture all" to extract all architectures
}

experiment-stages() {
    clone-systems
    extract-kconfig-models --with-kconfirm-smt y
}
