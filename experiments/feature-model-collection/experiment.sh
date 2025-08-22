#!/bin/bash
# The following line uses curl to reproducibly install and run the specified revision of torte.
# Alternatively, torte can be installed manually (see https://github.com/ekuiter/torte).
# In that case, make sure to check out the correct revision manually and run ./torte.sh <this-file>.
TORTE_REVISION=main; [[ $TOOL != torte ]] && builtin source /dev/stdin <<<"$(curl -fsSL https://raw.githubusercontent.com/ekuiter/torte/$TORTE_REVISION/torte.sh)" "$@"

# The point of this experiment file is to extract feature models for a large and representative selection of Kconfig-based configurable systems and their revisions.
# More information on some of the systems below can be found in Berger et al.'s "Variability Modeling in the Systems Software Domain" (DOI: 10.1109/TSE.2013.34).
# Our general strategy is to read feature models for all tagged Git revisions (provided that tags give a meaningful history).
# We usually compile dumpconf against the project source to get the most accurate translation.
# Sometimes this is not possible, then we use dumpconf compiled for a Linux version with a similar Kconfig dialect (in most projects, the Kconfig parser is cloned&owned from Linux).
# It is also possible to read feature models for any other tags/commits (e.g., for every commit that changes a Kconfig file), although usually very old versions won't work (because Kconfig might have only been introduced later) and very recent versions might also not work (because they use new/esoteric Kconfig features not supported by kconfigreader or dumpconf).

# The following Kconfig-based systems are deliberately no included right now:
# https://github.com/coreboot/coreboot uses a modified Kconfig with wildcards for the source directive
# https://github.com/Freetz/freetz uses Kconfig, but cannot be parsed with dumpconf, so we use freetz-ng instead (which is newer anyway)
# https://github.com/rhuitl/uClinux is not so easy to set up, because it depends on vendor files
# https://github.com/zephyrproject-rtos/zephyr also uses Kconfig, but a modified dialect based on Kconfiglib, which is not compatible with kconfigreader
# https://github.com/solettaproject/soletta not yet included, many models available at https://github.com/TUBS-ISF/soletta-case-study
# https://github.com/openwrt/openwrt not yet included

PATH_SEPARATOR=_ # create no nested directories
TIMEOUT=300 # timeout for extraction and transformation in seconds

experiment-systems() {
    add-axtls-kconfig-history --from release-1.0.0 --to release-2.0.0
    add-buildroot-kconfig-history --from 2009.05 --to 2022.05
    add-busybox-kconfig-history --from 1_3_0 --to 1_36_0
    add-embtoolkit-kconfig-history --from embtoolkit-1.0.0 --to embtoolkit-1.8.0
    add-fiasco-kconfig 5eed420385a9fc0055b06f063b4c981a68a35b51
    add-freetz-ng-kconfig d57a38e12ec6347ecdd4240fa541b722937fa72f
    add-linux-kconfig-history --from v6.0 --to v6.1
    #add-toybox-kconfig-history --from 0.4.5 --to 0.8.9
    add-uclibc-ng-kconfig-history --from v1.0.2 --to v1.0.40
}

experiment-stages() {
    # clone repositories and read committer dates
    clone-systems
    read-statistics
    
    # extract feature models
    extract-kconfig-models --output model
    join-into read-statistics model

    # transform into UVL
    transform-model-with-featjar --input model --transformer transform-model-to-uvl-with-featureide --output-extension uvl --timeout "$TIMEOUT"

    # CNF transformation
    transform-model-to-dimacs --input model --timeout "$TIMEOUT"
}

clean-up() {
    # clean up intermediate stages and rearrange output files
    clean clone-systems tag-linux-revisions read-statistics kconfigreader kclause \
        transform-model-to-model-with-featureide transform-model-to-smt-with-z3 transform-model-to-dimacs-with-kconfigreader \
        transform-model-to-dimacs-with-featjar transform-model-to-dimacs-with-featureide transform-smt-to-dimacs-with-z3 torte
    
    # Clean up files from the model stage (now numbered)
    local model_dir
    model_dir=$(stage-directory model)
    if [[ -d "$model_dir" ]]; then
        rm-safe \
            "$model_dir"/*binding* \
            "$model_dir"/*.features \
            "$model_dir"/*.rsf \
            "$model_dir"/*.kclause \
            "$model_dir"/*.kextractor
    fi
    
    # Clean up output files from all numbered stage directories
    rm-safe \
        "$STAGE_DIRECTORY"/*/*_"$OUTPUT_FILE_PREFIX"*.csv \
        "$STAGE_DIRECTORY"/*/*"$OUTPUT_FILE_PREFIX".*.csv \
        "$STAGE_DIRECTORY"/*/*.log \
        "$STAGE_DIRECTORY"/*/*.err
    
    # Move the UVL stage to a more convenient name
    local uvl_source_dir uvl_target_dir
    uvl_source_dir=$(stage-directory transform-model-to-uvl-with-featureide)
    uvl_target_dir=$(stage-directory uvl)
    if [[ -d "$uvl_source_dir" ]] && [[ ! -d "$uvl_target_dir" ]]; then
        mv "$uvl_source_dir" "$uvl_target_dir"
    fi
}