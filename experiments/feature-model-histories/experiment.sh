#!/bin/bash
# The following line uses curl to reproducibly install and run the specified revision of torte.
# Alternatively, torte can be installed manually (see https://github.com/ekuiter/torte).
# In that case, make sure to check out the correct revision manually and run ./torte.sh <this-file>.
TORTE_REVISION=main; [[ $TOOL != torte ]] && builtin source /dev/stdin <<<"$(curl -fsSL https://raw.githubusercontent.com/ekuiter/torte/$TORTE_REVISION/torte.sh)" "$@"

# The point of this experiment file is to extract feature-model histories for a wide selection of Kconfig-based configurable systems.
# More information on some of the systems below can be found on https://elias-kuiter.de/torte-research/.
# Our general strategy is to read feature models for all tagged Git revisions, provided that tags give a meaningful history, and a yearly sample.
# Mostly, we compile bindings from the LKC distributions included in the projects' source code to get the most accurate translation.
# It is also possible to read feature models for any other tags/commits (e.g., for every commit that changes a Kconfig file).
# However, usually very old versions won't work (because Kconfig might have only been introduced later).
# Very recent versions might also not work (because they use new/esoteric Kconfig features).
# No experimental features are enabled in this experiment (e.g., ConfigFix is disabled).

EXTRACT_TIMEOUT=1200 # timeout for extraction in seconds
TRANSFORM_TIMEOUT=30 # timeout for transformation in seconds

# define systems to extract here
SYSTEMS=(axtls barebox buildroot busybox coreboot crosstool-ng embtoolkit \
    entware freetz-ng l4re linux nuttx openadk openwrt ptxdist soletta \
    tizenrt toybox u-boot uclibc-ng uclibc uclibcxx uclinux-dist unikraft \
    xvisor)

# disable certain problematic combinations of system and extractor
add-restrictions-payload-file restrictions.csv

experiment-systems() {
    for system in "${SYSTEMS[@]}"; do
        if has-command add-"${system}"-kconfig-tags; then
            add-"${system}"-kconfig-tags
        fi
        add-"${system}"-kconfig-sample
    done
}

experiment-stages() {
    # clone repositories and read committer dates
    clone-systems
    read-statistics
    
    # extract feature models
    extract-kconfig-models --timeout "$EXTRACT_TIMEOUT" \
        --date-prefix "$(date-format)"
    join-into read-statistics extract-kconfig-models

    # # transform into UVL
    transform-to-uvl --timeout "$TRANSFORM_TIMEOUT"

    # # CNF transformation
    transform-to-dimacs --timeout "$TRANSFORM_TIMEOUT"
}

# execute this with "torte feature-model-histories clean-up" in the stages directory
clean-up() {
    rm -rf ./*_experiment
    rm -rf ./*_clone_systems
    rm -rf ./*_extract_kconfig_models_with_*
    rm -rf ./*_transform_model_to_dimacs_with_*
    rm -rf ./*_transform_model_to_model_with_featureide
    rm -rf ./*_transform_model_to_smt_with_z3
    rm -rf ./*_transform_smt_to_dimacs_with_z3
    # then zip the remaining stages and upload them into a torte release
}
