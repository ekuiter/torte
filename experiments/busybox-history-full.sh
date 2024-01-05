#!/bin/bash
# The following line uses curl to reproducibly install and run the specified revision of torte.
# Alternatively, torte can be installed manually (see https://github.com/ekuiter/torte).
# In that case, make sure to check out the correct revision manually and run ./torte.sh <this-file>.
TORTE_REVISION=main; [[ $TOOL != torte ]] && builtin source <(curl -fsSL https://raw.githubusercontent.com/ekuiter/torte/$TORTE_REVISION/torte.sh) "$@"

experiment-subjects() {
    add-busybox-kconfig-history --from 1_3_0 --to 1_36_1
    add-busybox-kconfig-history-full
}

experiment-stages() {
    clone-systems
    generate-busybox-models
    read-statistics
    extract-kconfig-models-with --extractor kmax
    join-into read-statistics kconfig
    transform-models-with-featjar --transformer model_to_uvl_featureide --output-extension uvl --timeout "$TIMEOUT"
    transform-models-into-dimacs --timeout "$TIMEOUT"
}

# can be executed from output directory to copy and rename model files
copy-models() {
    shopt -s globstar
    mkdir -p dimacs_clean/releases dimacs_clean/commits
    for f in model_to_dimacs_featureide/busybox/*.dimacs; do
        local revision
        local original_revision
        revision=$(basename "$f" .dimacs)
        cp "$f" "dimacs_clean/releases/$(date -d "@$(grep -E "^$revision," < read-statistics/output.csv | cut -d, -f4)" +"%Y%m%d%H%M%S")-$revision.dimacs"
    done
    for f in model_to_dimacs_featureide/busybox-models/*.dimacs; do
        local revision
        local original_revision
        revision=$(basename "$f" .dimacs | cut -d'[' -f1)
        original_revision=$(basename "$f" .dimacs | cut -d'[' -f2 | cut -d']' -f1)
        cp "$f" "dimacs_clean/commits/$(date -d "@$(grep -E "^$revision," < read-statistics/output.csv | cut -d, -f4)" +"%Y%m%d%H%M%S")-$original_revision.dimacs"
    done
    shopt -u globstar
}