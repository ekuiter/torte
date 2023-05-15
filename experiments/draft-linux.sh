#!/bin/bash
# The following line uses curl to reproducibly install and run the specified revision of torte.
# Alternatively, torte can be installed manually (see https://github.com/ekuiter/torte).
# In that case, make sure to check out the correct revision manually and run ./torte.sh <this-file>.
TORTE_REVISION=main; [[ $TOOL != torte ]] && builtin source <(curl -fsSL https://raw.githubusercontent.com/ekuiter/torte/$TORTE_REVISION/torte.sh) "$@"

TIMEOUT=200
ATTEMPTS=5
# FROM=v2.5.45
# TO=v6.4
FROM=v2.6.10
TO=v2.6.14

experiment-subjects() {
    #add-linux-kconfig-history --from "$FROM" --to "$TO" --architecture x86
    add-busybox-kconfig-history --from "1_10_0" --to "1_14_0"
}

experiment-stages() {
    clone-systems
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

    force
    #transform-models-with-featjar --transformer model_to_uvl_featureide --output-extension uvl --timeout "$TIMEOUT"
    #transform-models-with-featjar --transformer model_to_xml_featureide --output-extension xml --timeout "$TIMEOUT"
    transform-models-with-featjar --transformer model_to_smt_z3 --output-extension smt --timeout "$TIMEOUT" --jobs 0

    run \
        --stage dimacs \
        --image z3 \
        --input-directory model_to_smt_z3 \
        --command transform-into-dimacs-with-z3 \
        --timeout "$TIMEOUT" \
        --jobs 0
    join-into model_to_smt_z3 dimacs
    join-into kconfig dimacs

    compute-backbone --timeout "$TIMEOUT"  --jobs 0
    return
    
    solve --kind model-count --timeout "$TIMEOUT" --attempts "$ATTEMPTS" --reset-timeouts-at "$FROM" \
        --solver_specs \
        model-counting-competition-2022/d4.sh,solver,model-counting-competition-2022
        #model-counting-competition-2022/SharpSAT-td+Arjun/SharpSAT-td+Arjun.sh,solver,model-counting-competition-2022 \
        #model-counting-competition-2022/SharpSAT-TD/SharpSAT-TD.sh,solver,model-counting-competition-2022
        #model-counting-competition-2022/DPMC/DPMC.sh,solver,model-counting-competition-2022 \
        #model-counting-competition-2022/c2d.sh,solver,model-counting-competition-2022 \
        #model-counting-competition-2022/gpmc.sh,solver,model-counting-competition-2022 \
        #model-counting-competition-2022/TwG.sh,solver,model-counting-competition-2022 \
        #model-counting-competition-2022/d4.sh,solver,model-counting-competition-2022 # todo: second solver
    join-into dimacs solve_model-count

    log-output-field solve_model-count model-count
}