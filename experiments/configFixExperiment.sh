#!/bin/bash
# The following line uses curl to reproducibly install and run the specified revision of torte.
# Alternatively, torte can be installed manually (see https://github.com/ekuiter/torte).
# In that case, make sure to check out the correct revision manually and run ./torte.sh <this-file>.
TORTE_REVISION=main; [[ $TOOL != torte ]] && builtin source /dev/stdin <<<"$(curl -fsSL https://raw.githubusercontent.com/ekuiter/torte/$TORTE_REVISION/torte.sh)" "$@"

experiment-subjects() {
    add-linux-kconfig-history --from v6.7 --to v6.8 
    #add-busybox-kconfig-history --from 1_3_0 --to 1_3_1
    #add-busybox-kconfig-history --from 1_36_0 --to 1_36_1

}

experiment-stages() {
    clone-systems
    generate-busybox-models
    read-statistics
    extract-kconfig-models-with --extractor configfixextractor 
    transform-models-with-featjar --transformer model_to_uvl_featureide --output-extension uvl --timeout "$TIMEOUT"
    transform-models-into-dimacs --timeout "$TIMEOUT"
}
