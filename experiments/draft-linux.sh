#!/bin/bash
# The following line uses curl to reproducibly install and run the specified revision of torte.
# Alternatively, torte can be installed manually (see https://github.com/ekuiter/torte).
# In that case, make sure to check out the correct revision manually and run ./torte.sh <this-file>.
TORTE_REVISION=main; [[ $TOOL != torte ]] && builtin source <(curl -fsSL https://raw.githubusercontent.com/ekuiter/torte/$TORTE_REVISION/torte.sh) "$@"

# This experiment analyzes the feature model of Linux across a timespan of > 20 years (2002-2023)
# and across all its supported processor architectures. For each revision and architecture, a
# feature model is extracted with both kconfigreader and kmax and then transformed into various
# file formats using FeatureIDE (XML, UVL) and Z3 (DIMACS). Then, each feature model's core and dead
# features and its model count are computed, if possible.
# Note that this experiment is time- and space-intensive: The extraction phase alone takes about
# one week and 200GiB free disk space to run. While re-running the entire experiment is possible,
# it is probably not needed, depending on your use case (e.g., only analyzing the latest revision).

TIMEOUT=3 # timeout in seconds for all transformation and analysis steps (only exceeded when computing backbone and model count)
ATTEMPTS=2 # how many successive timeouts are allowed before giving up and moving on to the next extractor or architecture
FROM=v2.5.45 # first revision to analyze
TO=v6.4 # last revision to analyze

# temporary setting to run on external hard drive
OUTPUT_DIRECTORY=/run/media/ek/ITI-DBSE-Kuiter/new_output

experiment-subjects() {
    add-linux-kconfig-history --from "$FROM" --to "$TO" --architecture all
}

experiment-stages() {
    clone-systems
    tag-linux-revisions
    read-linux-names
    read-linux-architectures
    read-statistics
    read-statistics
    join-into read-statistics read-linux-names
    join-into read-statistics read-linux-architectures
    extract-kconfig-models
    return
    join-into read-statistics kconfig

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
    
    force
    solve --kind model-count --timeout "$TIMEOUT" --jobs "$ATTEMPTS" --attempts "$ATTEMPTS" --attempt-grouper "$(to-lambda linux-attempt-grouper)" \
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