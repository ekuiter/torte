#!/bin/bash
# The following line uses curl to reproducibly install and run the specified revision of torte.
# Alternatively, torte can be installed manually (see https://github.com/ekuiter/torte).
# In that case, make sure to check out the correct revision manually and run torte.sh <this-file>.
TORTE_REVISION=main; [[ -z $TOOL ]] && builtin source <(curl -fsSL https://raw.githubusercontent.com/ekuiter/torte/$TORTE_REVISION/torte.sh) "$@"

TIMEOUT=300
ATTEMPTS=5
# FROM=v2.5.45
# TO=v6.4
FROM=v2.6.10
TO=v2.6.11

experiment-subjects() {
    add-linux-kconfig-history --from "$FROM" --to "$TO" --architecture x86
}

experiment-stages() {
    #clone-systems
    #tag-linux-revisions
    # read-linux-names
    # read-linux-architectures
    #read-statistics
    #read-statistics skip-sloc
    # join-into read-statistics read-linux-names
    # join-into read-statistics read-linux-architectures
    #extract-kconfig-models
    extract-kconfig-models-with kmax
    #join-into read-statistics kconfig

    #transform-models-with-featjar --transformer model_to_uvl_featureide --output-extension uvl --timeout "$TIMEOUT"
    #transform-models-with-featjar --transformer model_to_xml_featureide --output-extension xml --timeout "$TIMEOUT"
    transform-models-with-featjar --transformer model_to_smt_z3 --output-extension smt --timeout "$TIMEOUT"

    run \
        --stage dimacs \
        --image z3 \
        --input-directory model_to_smt_z3 \
        --command transform-into-dimacs-with-z3 \
        --timeout "$TIMEOUT"
    join-into model_to_smt_z3 dimacs
    join-into kconfig dimacs

    solve --parser model-count --timeout "$TIMEOUT" --attempts "$ATTEMPTS" --reset-timeouts-at "$FROM" --solver_specs model-counting-competition-2022/d4.sh,solver # todo: second solver
    join-into dimacs solve_other_d4.sh
}