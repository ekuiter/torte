#!/bin/bash
# The following line uses curl to reproducibly install and run the specified revision of torte.
# Alternatively, torte can be installed manually (see https://github.com/ekuiter/torte).
# In that case, make sure to check out the correct revision manually and run ./torte.sh <this-file>.
TORTE_REVISION=main; [[ $TOOL != torte ]] && builtin source /dev/stdin <<<"$(curl -fsSL https://raw.githubusercontent.com/ekuiter/torte/$TORTE_REVISION/torte.sh)" "$@"

TIMEOUT=3600
# parameters for computing model count
SOLVE_TIMEOUT=3600 # timeout in seconds
SOLVE_JOBS=4 # number of parallel jobs to run, should not exceed number of attempts
SOLVE_ATTEMPTS=4 # how many successive timeouts are allowed before giving up and moving on

experiment-subjects() {
    #All versions
    #add-toybox-kconfig-history 
    #add-uclibc-ng-kconfig-history
    #add-embtoolkit-kconfig-history
    add-fiasco-kconfig 58aa50a8aae2e9396f1c8d1d0aa53f2da20262ed
    #add-freetz-ng-kconfig 5c5a4d1d87ab8c9c6f121a13a8fc4f44c79700af
    #add-axtls-kconfig-history
    #add-busybox-kconfig-history
    #add-buildroot-kconfig-history
    #add-linux-kconfig-history --from v2.5.45 --to v6.12


    #--architecture all
    #add-linux-kconfig-history --from v6.7 --to v6.8 
    
    # vor V5 funktioniert bei configFix nicht
    #add-linux-kconfig-history --from v5.0  --to v5.1
    #add-linux-kconfig-history --from v6.10 --to v6.10
    #1_1_0 --to 1_4_2 Fehler , die ich nicht fixen konnte
    # --from 0.32 --to 1.01  kconfig file Config.in does not exist
    #add-busybox-kconfig-history --from 1_5_1 --to 1_5_2
    #add-busybox-kconfig-history --from 1_36_1
    #add-axtls-kconfig-history --from release-1.0.0 --to release-1.0.1
    #add-axtls-kconfig-history --from release-2.0.0
    #add-embtoolkit-kconfig-history --from embtoolkit-0.1.0 --to embtoolkit-1.0.0
    #add-embtoolkit-kconfig-history --from embtoolkit-1.8.0
    #toybox :0.0.1  bei Kmax und kconfigreader funktioniert nicht
    #add-toybox-kconfig-history --from 0.0.2 --to 0.0.3
    #add-toybox-kconfig-history --from 0.8.11
    #Problematish
    #uclibc-ng
    #add-uclibc-ng-kconfig-history --from v1.0.0 --to v1.0.1
    #add-uclibc-ng-kconfig-history --from v1.0.47
    
    
    #add-buildroot-kconfig-history --from 2021.11.2 --to 2021.11.3

}

experiment-stages() {
    clone-systems
    #read-statistics
    #read-embtoolkit-configs
    #extract-kconfig-models-with --extractor configfixextractor 
    #extract-kconfig-models-with --extractor kconfigreader
    extract-kconfig-models-with --extractor kmax
    #extract-kconfig-models

    #compute-unconstrained-features

    # transform
    #transform-models-with-featjar --transformer model_to_uvl_featureide --output-extension uvl --jobs 2
    #transform-models-with-featjar --transformer model_to_xml_featureide --output-extension xml --jobs 2
    #transform-models-with-featjar --transformer model_to_smt_z3 --output-extension smt --jobs 2
    #run \
        #--stage dimacs \
        #--image z3 \
        #--input-directory model_to_smt_z3 \
        #--command transform-into-dimacs-with-z3 \
        #--jobs 2
    #join-into model_to_smt_z3 dimacs
    #join-into kconfig dimacs

    # analyze
    #compute-backbone-dimacs-with-cadiback 
    #join-into dimacs backbone-dimacs
    #compute-backbone-features --jobs 16
   # solve \
        #--input-stage backbone-dimacs \
        #--input-extension backbone.dimacs \
        #--kind model-count \
        #--timeout "$SOLVE_TIMEOUT" \
        #--jobs "$SOLVE_JOBS" \
        #--attempts "$SOLVE_ATTEMPTS" \
        #--attempt-grouper "$(to-lambda linux-attempt-grouper)" \
        #--solver_specs \
        #model-counting-competition-2022/d4.sh,solver,model-counting-competition-2022 \
        #model-counting-competition-2022/SharpSAT-td+Arjun/SharpSAT-td+Arjun.sh,solver,model-counting-competition-2022
    #join-into backbone-dimacs solve_model-count
}
