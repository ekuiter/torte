#!/bin/bash
# The following line uses curl to reproducibly install and run the specified revision of torte.
# Alternatively, torte can be installed manually (see https://github.com/ekuiter/torte).
# In that case, make sure to check out the correct revision manually and run ./torte.sh <this-file>.
TORTE_REVISION=main; [[ $TOOL != torte ]] && builtin source /dev/stdin <<<"$(curl -fsSL https://raw.githubusercontent.com/ekuiter/torte/$TORTE_REVISION/torte.sh)" "$@"

# Extraction and comparison of all feature models of several feature-model histories

PASSES=(releases commits)

experiment-systems() {
    case "$PASS" in
        releases)
        add-busybox-kconfig-history --from 1_3_0 --to 1_36_1
        add-axtls-kconfig-history --from release-1.0.0 --to release-2.0.0
        add-uclibc-ng-kconfig-history --from v1.0.2 --to v1.0.40
        add-toybox-kconfig-history --from 0.4.5 --to 0.8.9
        add-embtoolkit-kconfig-history --from embtoolkit-1.0.0 --to embtoolkit-1.8.0 ;;
        commits) # todo: test this (what about duplicate files? what about the sorting of the files in the right order for diffing?)
        add-busybox-kconfig-history-commits ;;
    esac
}

experiment-test-systems() {
    case "$PASS" in
        releases)
        add-axtls-kconfig-history --from release-1.0.0 --to release-1.0.2 ;;
        commits) ;;
    esac
}

experiment-stages() {
    clone-systems
    [[ "$PASS" == commits ]] && generate-busybox-models
    read-statistics
    extract-kconfig-models --with-kconfigreader y --with-kclause y
    join-into read-statistics extract-kconfig-models
    compute-file-pairs --file-field model_file
    diff-with-clausy \
        --file-field model_file \
        --timeout 300
}