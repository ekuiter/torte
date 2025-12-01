#!/bin/bash
# The following line uses curl to reproducibly install and run the specified revision of torte.
# Alternatively, torte can be installed manually (see https://github.com/ekuiter/torte).
# In that case, make sure to check out the correct revision manually and run ./torte.sh <this-file>.
TORTE_REVISION=main; [[ $TOOL != torte ]] && builtin source /dev/stdin <<<"$(curl -fsSL https://raw.githubusercontent.com/ekuiter/torte/$TORTE_REVISION/torte.sh)" "$@"

# This experiment extracts, transforms, and solves a single feature model.
# It serves as a demo and integration test for torte and also returns some common statistics of the model.
# Some lines are commented out here to speed up the experiment for demonstration purposes.

# here we define global experiment parameters, which are passed to the stages that need them below
with_timeout="--timeout 10"
with_jobs="--jobs 4"

add-payload-file evaluation.ipynb # we can add Jupyter notebooks to execute at the end of the experiment
# add-payload-file Kconfig.test # we can inject individual KConfig files to test extraction on small examples
# download-payload-file smart_home_fm.uvl https://www.uvlhub.io/hubfiles/download/189 # we can also download arbitrary payload files from the web
# download-payload-file Tankwar.dimacs \
#     https://raw.githubusercontent.com/SoftVarE-Group/feature-model-benchmark/refs/heads/master/feature_models/dimacs/games/Tankwar/Schulze2012.dimacs

experiment-systems() {
    # usually we extract feature models from KConfig-specified ground truth ...
    add-busybox-kconfig-history --from 1_36_0 --to 1_36_1 # typically, we add (excerpts of) system histories to analyze
    # add-kconfig-payload-file Kconfig.test # we can also just analyze one KConfig file, which will be parsed with Linux's LKC implementation
    
    # ... but we can also inject pre-existing feature model files directly
    # here, any files are legal that can be successfully parsed by subsequent stages (typically FeatJAR or FeatureIDE)
    # this allows us to integrate with feature-model repositories, such as the feature-model benchmark or UVLHub (where we download these files from)
    # add-model-payload-file smart_home_fm.uvl
    # add-model-payload-file Tankwar.dimacs
}

experiment-test-systems() {
    # only extract BusyBox in test mode and CI pipeline
    add-busybox-kconfig-history --from 1_36_0 --to 1_36_1
}

# shellcheck disable=SC2086
experiment-stages() {
    clone-systems
    read-statistics
    extract-kconfig-models --with_kconfigreader y --with_kclause y --with_configfix y

    transform-to-xml $with_timeout
    transform-to-uvl $with_timeout
    transform-to-dimacs --with_featureide y --with_featjar y --with_kconfigreader y --with_z3 y $with_timeout
    join-into extract-kconfig-models transform-to-dimacs

    draw-community-structure-with-satgraf $with_timeout
    transform-dimacs-to-backbone-dimacs-with --transformer cadiback $with_timeout
    compute-unconstrained-features $with_timeout
    extract-kconfig-hierarchies-with-kconfiglib $with_timeout
    compute-backbone-features $with_timeout

    solve-sat $with_jobs $with_timeout
    solve-sharp-sat $with_jobs $with_timeout

    log-output-field read-statistics source_lines_of_code
    log-output-field extract-kconfig-models model_features
    log-output-field transform-to-dimacs dimacs_variables
    log-output-field solve-sat sat
    log-output-field solve-sharp-sat sharp_sat
    run-jupyter-notebook --input draw-community-structure-with-satgraf --payload-file evaluation.ipynb
}