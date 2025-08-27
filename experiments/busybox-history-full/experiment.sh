#!/bin/bash
# The following line uses curl to reproducibly install and run the specified revision of torte.
# Alternatively, torte can be installed manually (see https://github.com/ekuiter/torte).
# In that case, make sure to check out the correct revision manually and run ./torte.sh <this-file>.
TORTE_REVISION=main; [[ $TOOL != torte ]] && builtin source /dev/stdin <<<"$(curl -fsSL https://raw.githubusercontent.com/ekuiter/torte/$TORTE_REVISION/torte.sh)" "$@"

# Extraction of all feature models of BusyBox; in the first pass for all tagged releases, in the second pass, for every commit that touches the feature model.
PASSES=(releases full)

experiment-systems() {
    case "$PASS" in
        releases) add-busybox-kconfig-history --from 1_00 --to 1_36_1 ;;
        full) add-busybox-kconfig-history-full ;;
    esac
}

experiment-test-systems() {
    case "$PASS" in
        releases) add-busybox-kconfig-history --from 1_36_0 --to 1_36_1 ;;
        full) ;;
    esac
}

experiment-stages() {
    clone-systems
    local input=
    if [[ "$PASS" == "full" ]]; then
        generate-busybox-models
        input=generate-busybox-models
    fi
    read-statistics --input "$input"
    extract-kconfig-models-with --extractor kclause --input "$input" --output extract-kconfig-models
    join-into read-statistics extract-kconfig-models
    transform-model-with-featjar --transformer transform-model-to-uvl-with-featureide --output-extension uvl
    transform-model-to-dimacs
}

# can be executed from output directory to copy and rename model files
copy-models() {
    mkdir -p dimacs_clean/releases dimacs_clean/commits
    for f in transform-model-to-dimacs-with-featureide/busybox/*.dimacs; do
        local revision
        local original_revision
        revision=$(basename "$f" .dimacs)
        cp "$f" "dimacs_clean/releases/$(date -d "@$(grep -E "^$revision," < read-statistics/"$OUTPUT_FILE_PREFIX".csv | cut -d, -f4)" +"%Y%m%d%H%M%S")-$revision.dimacs"
    done
    for f in transform-model-to-dimacs-with-featureide/busybox-models/*.dimacs; do
        local revision
        local original_revision
        revision=$(basename "$f" .dimacs | cut -d'[' -f1)
        original_revision=$(basename "$f" .dimacs | cut -d'[' -f2 | cut -d']' -f1)
        cp "$f" "dimacs_clean/commits/$(date -d "@$(grep -E "^$revision," < read-statistics/"$OUTPUT_FILE_PREFIX".csv | cut -d, -f4)" +"%Y%m%d%H%M%S")-$original_revision.dimacs"
    done
}