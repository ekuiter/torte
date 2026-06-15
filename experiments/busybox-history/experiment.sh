#!/bin/bash
# The following line uses curl to reproducibly install and run the specified revision of torte.
# Alternatively, torte can be installed manually (see https://github.com/ekuiter/torte).
# In that case, make sure to check out the correct revision manually and run ./torte.sh <this-file>.
TORTE_REVISION=main; [[ $TOOL != torte ]] && builtin source /dev/stdin <<<"$(curl -fsSL https://raw.githubusercontent.com/ekuiter/torte/$TORTE_REVISION/torte.sh)" "$@"

# Extraction of all feature models of BusyBox; in the first pass for all tagged releases, in the second pass, for every commit that touches the feature model.
PASSES=(releases commits)

experiment-systems() {
    case "$PASS" in
        releases) add-busybox-kconfig-tags ;;
        commits) add-busybox-kconfig-commits ;;
    esac
}

experiment-test-systems() {
    case "$PASS" in
        releases) add-busybox-kconfig-tags --from 1_38_0 --to 1_39_0 ;;
        commits) ;;
    esac
}

experiment-stages() {
    clone-systems
    read-statistics
    extract-kconfig-models --with-kclause y
    join-into read-statistics extract-kconfig-models
    transform-to-uvl
    transform-to-dimacs

    collect-stage-files --input transform-to-dimacs-with-featureide --extension dimacs
    collect-stage-files --input transform-to-uvl-with-featureide --extension uvl
}
