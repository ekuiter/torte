#!/bin/bash
# The following line uses curl to reproducibly install and run the specified revision of torte.
# Alternatively, torte can be installed manually (see https://github.com/ekuiter/torte).
# In that case, make sure to check out the correct revision manually and run ./torte.sh <this-file>.
TORTE_REVISION=44c7f0f; [[ $TOOL != torte ]] && builtin source <(curl -fsSL https://raw.githubusercontent.com/ekuiter/torte/$TORTE_REVISION/torte.sh) "$@"

# This experiment extracts and transforms a single feature model from a recent revision of the Linux kernel.

experiment-subjects() {
    add-linux-kconfig-history --from v6.5 --to v6.6 --architecture x86
}

experiment-stages() {
    # extract
    clone-systems
    extract-kconfig-models
    compute-unconstrained-features

    # transform
    transform-models-with-featjar --transformer model_to_uvl_featureide --output-extension uvl --jobs 2
    transform-models-with-featjar --transformer model_to_xml_featureide --output-extension xml --jobs 2
    transform-models-with-featjar --transformer model_to_smt_z3 --output-extension smt --jobs 2
    run \
        --stage dimacs \
        --image z3 \
        --input-directory model_to_smt_z3 \
        --command transform-into-dimacs-with-z3 \
        --jobs 2
    join-into model_to_smt_z3 dimacs
    join-into kconfig dimacs
}