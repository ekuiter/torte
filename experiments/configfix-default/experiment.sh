#!/bin/bash
# The following line uses curl to reproducibly install and run the specified revision of torte.
# Alternatively, torte can be installed manually (see https://github.com/ekuiter/torte).
# In that case, make sure to check out the correct revision manually and run ./torte.sh <this-file>.
TORTE_REVISION=main; [[ $TOOL != torte ]] && builtin source /dev/stdin <<<"$(curl -fsSL https://raw.githubusercontent.com/ekuiter/torte/$TORTE_REVISION/torte.sh)" "$@"

# This experiment extracts, transforms, and analyzes a single feature model.
# It serves as a demo and integration test for torte and also returns some common statistics of the model.

TIMEOUT=10

experiment-systems() {
    #Problem mit source (Frage?)
    #add-busybox-kconfig-history --from 1_36_0 --to 1_36_1
    
    # x86  arm64 ,openrisc and arc linux done
    add-linux-kconfig-history --from v6.7 --to v6.8
    
    #Nicht für alle Architekturen
    #add-linux-kconfig-history --from v2.5.45 --to v2.5.46 --architecture all 
    #add-busybox-kconfig-history-full
}

experiment-test-systems() {
    # test with just the latest version and x86_64 architecture for speed
    add-linux-kconfig-history --from v6.8 --to v6.8 --architecture x86_64
}

experiment-stages() {
    clone-systems
    read-statistics
    extract-kconfig-models-with --extractor configfix
}
