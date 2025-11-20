#!/bin/bash
# The following line uses curl to reproducibly install and run the specified revision of torte.
# Alternatively, torte can be installed manually (see https://github.com/ekuiter/torte).
# In that case, make sure to check out the correct revision manually and run ./torte.sh <this-file>.
TORTE_REVISION=main; [[ $TOOL != torte ]] && builtin source /dev/stdin <<<"$(curl -fsSL https://raw.githubusercontent.com/ekuiter/torte/$TORTE_REVISION/torte.sh)" "$@"

# This experiment extracts, transforms, and solves a single feature model.
# It serves as a demo and integration test for torte and also returns some common statistics of the model.

# here we define global configuration variables, which are explicitly passed to stages below
TIMEOUT=10
JOBS=4

add-payload-file evaluation.ipynb # we can add Jupyter notebooks to execute at the end of the experiment
# add-payload-file Kconfig.test # we can inject individual KConfig files to test extraction on small examples
# download-payload-file smart_home_fm.uvl https://www.uvlhub.io/hubfiles/download/189 # we can also download arbitrary payload files from the web
# download-payload-file Tankwar.dimacs \
#     https://raw.githubusercontent.com/SoftVarE-Group/feature-model-benchmark/refs/heads/master/feature_models/dimacs/games/Tankwar/Schulze2012.dimacs
# (the previous lines are commented out here for demonstration purposes, to focus on the BusyBox model)

experiment-systems() {
    add-busybox-kconfig-history --from 1_36_0 --to 1_36_1 # usually, we add (excerpts of) system histories to analyze here
    # add-payload-file-kconfig Kconfig.test # we can also just analyze one KConfig file, which will be parsed with the original LKC implementation in Linux
    # (the previous line is commented out here for demonstration purposes, because it will cause Linux to be cloned, which takes some time and space)
}

experiment-test-systems() {
    add-busybox-kconfig-history --from 1_36_0 --to 1_36_1
}

experiment-stages() {
    clone-systems
    read-statistics

    # usually we extract KConfig models from ground truth ...
    extract-kconfig-models

    # ... but we can also inject pre-existing feature model files directly
    # here, any files are legal that can be successfully parsed by subsequent stages (typically FeatJAR or FeatureIDE)
    # this allows us to integrate with feature-model repositories, such as the feature-model benchmark or UVLHub (where we download these files from)
    # inject-feature-models --payload-files smart_home_fm.uvl Tankwar.dimacs
    # (the previous line is commented out here for demonstration purposes, to focus on the BusyBox model)

    transform-with-featjar --transformer transform-to-xml-with-featureide --output-extension xml --timeout "$TIMEOUT"
    transform-with-featjar --transformer transform-to-uvl-with-featureide --output-extension uvl --timeout "$TIMEOUT"
    transform-to-dimacs --timeout "$TIMEOUT"

    draw-community-structure-with-satgraf --timeout "$TIMEOUT"
    transform-dimacs-to-backbone-dimacs-with --transformer cadiback --timeout "$TIMEOUT"
    compute-unconstrained-features --timeout "$TIMEOUT"
    extract-kconfig-hierarchies-with-kconfiglib --timeout "$TIMEOUT"
    compute-backbone-features --timeout "$TIMEOUT"
    solve-sat --jobs "$JOBS" --timeout "$TIMEOUT"
    solve-sharp-sat --jobs "$JOBS" --timeout "$TIMEOUT"

    join-into extract-kconfig-models transform-to-dimacs
    join-into transform-to-dimacs draw-community-structure-with-satgraf
    join-into transform-to-dimacs solve-sat
    join-into transform-to-dimacs solve-sharp-sat

    log-output-field read-statistics source_lines_of_code
    log-output-field extract-kconfig-models model_features
    log-output-field transform-to-dimacs dimacs_variables
    log-output-field solve-sat sat
    log-output-field solve-sharp-sat sharp_sat
    run-jupyter-notebook --input draw-community-structure-with-satgraf --payload-file evaluation.ipynb
}