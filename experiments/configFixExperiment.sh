#!/bin/bash
# The following line uses curl to reproducibly install and run the specified revision of torte.
# Alternatively, torte can be installed manually (see https://github.com/ekuiter/torte).
# In that case, make sure to check out the correct revision manually and run ./torte.sh <this-file>.
TORTE_REVISION=main; [[ $TOOL != torte ]] && builtin source /dev/stdin <<<"$(curl -fsSL https://raw.githubusercontent.com/ekuiter/torte/$TORTE_REVISION/torte.sh)" "$@"

experiment-subjects() {
    #All versions
    #add-toybox-kconfig-history 
    #add-uclibc-ng-kconfig-history
    #add-embtoolkit-kconfig-history
    #add-fiasco-kconfig 58aa50a8aae2e9396f1c8d1d0aa53f2da20262ed
    #add-freetz-ng-kconfig 5c5a4d1d87ab8c9c6f121a13a8fc4f44c79700af
    #add-axtls-kconfig-history
    #add-busybox-kconfig-history
    #add-linux-kconfig-history --from v2.5.45 --to v6.12
    #add-buildroot-kconfig-history

    #--architecture all
    add-linux-kconfig-history --from v6.7 --to v6.8 
    
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
    extract-kconfig-models-with --extractor configfixextractor 
    #extract-kconfig-models-with --extractor kconfigreader
    #extract-kconfig-models-with --extractor kmax
    
    #compute-unconstrained-features --jobs 16


    #extract-kconfig-models
 

    # transform
    #transform-models-with-featjar --transformer model_to_uvl_featureide --output-extension uvl --jobs 16
    #transform-models-with-featjar --transformer model_to_xml_featureide --output-extension xml --jobs 16
    transform-models-into-dimacs --timeout "$TIMEOUT"
    
    # Bei ConfigFix funktioniert nicht 
    #compute-unconstrained-features --timeout "$TIMEOUT"
    compute-backbone-dimacs-with-cadiback --jobs 16
    compute-backbone-features --jobs 16

    

    #evaluate
    #run-notebook --file experiments/ConfigFix.ipynb
}
