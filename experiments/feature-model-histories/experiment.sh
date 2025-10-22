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

TIMEOUT=600 # timeout for extraction and transformation in seconds

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
    extract-kconfig-models --timeout "$TIMEOUT"
    join-into read-statistics extract-kconfig-models

    # transform into UVL
    transform-model-with-featjar --transformer transform-model-to-uvl-with-featureide --output-extension uvl --timeout "$TIMEOUT"
    
    # CNF transformation
    transform-model-to-dimacs --timeout "$TIMEOUT"

    # collect-stage-files --input transform-model-to-dimacs-with-featureide --extension dimacs
    # collect-stage-files --input transform-model-to-uvl-with-featureide --extension uvl
}

# clean-up() {
#     # clean up intermediate stages and rearrange output files
#     clean clone-systems tag-linux-revisions read-statistics kconfigreader kclause \
#         transform-model-to-model-with-featureide transform-model-to-smt-with-z3 transform-model-to-dimacs-with-kconfigreader \
#         transform-model-to-dimacs-with-featjar transform-model-to-dimacs-with-featureide transform-smt-to-dimacs-with-z3 torte
    
#     # Clean up files from the model stage (now numbered)
#     local model_dir
#     model_dir=$(stage-directory model)
#     if [[ -d "$model_dir" ]]; then
#         rm-safe \
#             "$model_dir"/*binding* \
#             "$model_dir"/*.features \
#             "$model_dir"/*.rsf \
#             "$model_dir"/*.kclause \
#             "$model_dir"/*.kextractor
#     fi
    
#     # Clean up output files from all numbered stage directories
#     rm-safe \
#         "(stages-directory)"/*/*_"$OUTPUT_FILE_PREFIX"*.csv \
#         "(stages-directory)"/*/*"$OUTPUT_FILE_PREFIX".*.csv \
#         "(stages-directory)"/*/*.log \
#         "(stages-directory)"/*/*.err

#     # Move the UVL stage to a more convenient name
#     local uvl_source_dir uvl_target_dir
#     uvl_source_dir=$(stage-directory transform-model-to-uvl-with-featureide)
#     uvl_target_dir=$(stage-directory uvl)
#     if [[ -d "$uvl_source_dir" ]] && [[ ! -d "$uvl_target_dir" ]]; then
#         mv "$uvl_source_dir" "$uvl_target_dir"
#     fi
# }