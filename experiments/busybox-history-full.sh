#!/bin/bash
# The following line uses curl to reproducibly install and run the specified revision of torte.
# Alternatively, torte can be installed manually (see https://github.com/ekuiter/torte).
# In that case, make sure to check out the correct revision manually and run ./torte.sh <this-file>.
TORTE_REVISION=main; [[ $TOOL != torte ]] && builtin source <(curl -fsSL https://raw.githubusercontent.com/ekuiter/torte/$TORTE_REVISION/torte.sh) "$@"

experiment-subjects() {
    add-busybox-kconfig-history-full
}

experiment-stages() {
    clone-systems
    generate-busybox-models
    read-statistics
    extract-kconfig-models
    join-into read-statistics kconfig
}

# todo: rename and add timestamps in file name; remove obvious duplicate models that do not differ