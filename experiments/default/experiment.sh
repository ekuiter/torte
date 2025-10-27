#!/bin/bash
# The following line uses curl to reproducibly install and run the specified revision of torte.
# Alternatively, torte can be installed manually (see https://github.com/ekuiter/torte).
# In that case, make sure to check out the correct revision manually and run ./torte.sh <this-file>.
TORTE_REVISION=main; [[ $TOOL != torte ]] && builtin source /dev/stdin <<<"$(curl -fsSL https://raw.githubusercontent.com/ekuiter/torte/$TORTE_REVISION/torte.sh)" "$@"

# This experiment extracts, transforms, and solves a single feature model.
# It serves as a demo and integration test for torte and also returns some common statistics of the model.

TIMEOUT=10
JOBS=4

add-payload-file evaluation.ipynb

experiment-systems() {
    add-busybox-kconfig-history --from 1_36_0 --to 1_36_1
}

experiment-test-systems() {
    add-busybox-kconfig-history --from 1_36_0 --to 1_36_1
}

experiment-stages() {
    clone-systems
    read-statistics
    extract-kconfig-models

    transform-model-with-featjar --transformer transform-model-to-xml-with-featureide --output-extension xml --timeout "$TIMEOUT"
    transform-model-with-featjar --transformer transform-model-to-uvl-with-featureide --output-extension uvl --timeout "$TIMEOUT"
    transform-model-to-dimacs --timeout "$TIMEOUT"
    
    draw-community-structure-with-satgraf --timeout "$TIMEOUT"
    transform-dimacs-to-backbone-dimacs-with --transformer cadiback --timeout "$TIMEOUT"
    compute-unconstrained-features --timeout "$TIMEOUT"
    compute-backbone-features --timeout "$TIMEOUT"
    solve-sat --jobs "$JOBS" --timeout "$TIMEOUT"
    solve-sharp-sat --jobs "$JOBS" --timeout "$TIMEOUT"

    join-into extract-kconfig-models transform-model-to-dimacs
    join-into transform-model-to-dimacs draw-community-structure-with-satgraf
    join-into transform-model-to-dimacs solve-sat
    join-into transform-model-to-dimacs solve-sharp-sat

    log-output-field read-statistics source_lines_of_code
    log-output-field extract-kconfig-models model_features
    log-output-field transform-model-to-dimacs dimacs_variables
    log-output-field solve-sat sat
    log-output-field solve-sharp-sat sharp_sat
    run-jupyter-notebook --input draw-community-structure-with-satgraf --payload-file evaluation.ipynb
}