#!/bin/bash
# The following line uses curl to reproducibly install and run the specified revision of torte.
# Alternatively, torte can be installed manually (see https://github.com/ekuiter/torte).
# In that case, make sure to check out the correct revision manually and run ./torte.sh <this-file>.
TORTE_REVISION=main; [[ $TOOL != torte ]] && builtin source /dev/stdin <<<"$(curl -fsSL https://raw.githubusercontent.com/ekuiter/torte/$TORTE_REVISION/torte.sh)" "$@"

# The point of this experiment file is to extract feature-model histories for a representative selection of Kconfig-based configurable systems.
# More information on some of the systems below can be found in Berger et al.'s "Variability Modeling in the Systems Software Domain" (DOI: 10.1109/TSE.2013.34).
# Our general strategy is to read feature models for all tagged Git revisions, provided that tags give a meaningful history, or a yearly sample otherwise.
# Usually, we compile bindings from the LKC distributions included in the projects' source code to get the most accurate translation.
# It is also possible to read feature models for any other tags/commits (e.g., for every commit that changes a Kconfig file).
# However,  usually very old versions won't work (because Kconfig might have only been introduced later).
# Very recent versions might also not work (because they use new/esoteric Kconfig features).

EXTRACT_TIMEOUT=600 # timeout for extraction in seconds
TRANSFORM_TIMEOUT=60 # timeout for transformation in seconds

experiment-systems() {
    add-axtls-kconfig-history
    add-buildroot-kconfig-history
    add-busybox-kconfig-history
    add-embtoolkit-kconfig-history
    add-freetz-ng-kconfig-history
    add-l4re-kconfig-history
    add-linux-kconfig-history
    add-toybox-kconfig-history
    add-uclibc-kconfig-history
    add-uclibc-ng-kconfig-history
}

experiment-stages() {
    # clone repositories and read committer dates
    clone-systems
    read-statistics
    
    # extract feature models
    extract-kconfig-models --timeout "$EXTRACT_TIMEOUT"
    join-into read-statistics extract-kconfig-models

    # transform into UVL
    transform-model-with-featjar --transformer transform-model-to-uvl-with-featureide --output-extension uvl --timeout "$TRANSFORM_TIMEOUT"

    # CNF transformation
    transform-model-to-dimacs --timeout "$TRANSFORM_TIMEOUT"
}