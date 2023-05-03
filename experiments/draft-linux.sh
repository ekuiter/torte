#!/bin/bash
# The following line uses curl to reproducibly install and run the specified revision of torte.
# Alternatively, torte can be installed manually (see https://github.com/ekuiter/torte).
# In that case, make sure to check out the correct revision manually and run torte.sh <this-file>.
TORTE_REVISION=main; [[ -z $DOCKER_PREFIX ]] && builtin source <(curl -fsSL https://raw.githubusercontent.com/ekuiter/torte/$TORTE_REVISION/torte.sh) "$@"

TIMEOUT=1800

experiment-subjects() {
    add-linux-kconfig-history --from v2.5.45 --to v6.4
}

experiment-stages() {
    force

    clone-systems
    tag-linux-revisions
    read-linux-names
    read-statistics
    join-into read-linux-names read-statistics
    extract-kconfig-models
    join-into read-statistics kconfig

    transform-models-with-featjar --transformer model_to_uvl_featureide --output-extension uvl --timeout "$timeout"
    transform-models-with-featjar --transformer model_to_xml_featureide --output-extension xml --timeout "$timeout"
    transform-models-with-featjar --transformer model_to_smt_z3 --output-extension smt --timeout "$timeout"

    run \
        --stage dimacs \
        --image z3 \
        --input-directory model_to_smt_z3 \
        --command transform-into-dimacs-with-z3 \
        --timeout "$timeout"
    join-into model_to_smt_z3 dimacs
    join-into kconfig dimacs

    solve --parser model-count --timeout "$timeout" --solver_specs other/d4.sh,solver # todo: second solver
}