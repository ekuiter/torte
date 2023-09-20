#!/bin/bash
# The following line uses curl to reproducibly install and run the specified revision of torte.
# Alternatively, torte can be installed manually (see https://github.com/ekuiter/torte).
# In that case, make sure to check out the correct revision manually and run ./torte.sh <this-file>.
TORTE_REVISION=fcc73a5; [[ $TOOL != torte ]] && builtin source <(curl -fsSL https://raw.githubusercontent.com/ekuiter/torte/$TORTE_REVISION/torte.sh) "$@"

# This experiment extracts, transforms, and analyzes a single feature model.
# It serves as a demo and integration test for torte and also returns some common statistics of the model.

TIMEOUT=3

experiment-subjects() {
    add-busybox-kconfig-history --from 1_36_0 --to 1_36_1
}

experiment-stages() {
    clone-systems
    read-statistics
    extract-kconfig-models
    
    transform-models-with-featjar --transformer model_to_xml_featureide --output-extension xml --timeout "$TIMEOUT"
    transform-models-with-featjar --transformer model_to_uvl_featureide --output-extension uvl --timeout "$TIMEOUT"
    transform-models-into-dimacs --timeout "$TIMEOUT"
    
    draw-community-structure --timeout "$TIMEOUT"
    solve-satisfiable --timeout "$TIMEOUT"
    solve-model-count --timeout "$TIMEOUT"

    join-into kconfig dimacs
    join-into dimacs community-structure
    join-into dimacs solve_satisfiable
    join-into dimacs solve_model-count

    log-output-field read-statistics source_lines_of_code
    log-output-field kconfig model-features
    log-output-field dimacs dimacs-variables
    log-output-field solve_satisfiable satisfiable
    log-output-field solve_model-count model-count
}