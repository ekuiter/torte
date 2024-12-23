#!/bin/bash
# The following line uses curl to reproducibly install and run the specified revision of torte.
# Alternatively, torte can be installed manually (see https://github.com/ekuiter/torte).
# In that case, make sure to check out the correct revision manually and run ./torte.sh <this-file>.
TORTE_REVISION=main; [[ $TOOL != torte ]] && builtin source /dev/stdin <<<"$(curl -fsSL https://raw.githubusercontent.com/ekuiter/torte/$TORTE_REVISION/torte.sh)" "$@"

experiment-subjects() {
    add-linux-kconfig-history --from v6.7 --to v6.8 
    #add-busybox-kconfig-history --from 1_36_0 --to 1_36_1
    #add-axtls-kconfig-history --from release-2.0.0 --to release-2.0.1
    #add-embtoolkit-kconfig-history --from embtoolkit-1.8.0 --to embtoolkit-1.8.1
    #add-fiasco-kconfig 58aa50a8aae2e9396f1c8d1d0aa53f2da20262ed
    #add-freetz-ng-kconfig 5c5a4d1d87ab8c9c6f121a13a8fc4f44c79700af
    #add-uclibc-ng-kconfig-history --from v1.0.40 --to v1.0.41
    #add-toybox-kconfig-history --from 0.4.5 --to 0.8.9
    #Problematish
    #add-buildroot-kconfig-history --from 2021.11.2 --to 2021.11.3

}

experiment-stages() {
    clone-systems
    extract-kconfig-models-with --extractor configfixextractor 
    #extract-kconfig-models-with --extractor kconfigreader
    
    # transform
    transform-models-with-featjar --transformer model_to_uvl_featureide --output-extension uvl --jobs 2
    transform-models-with-featjar --transformer model_to_xml_featureide --output-extension xml --jobs 2
    transform-models-into-dimacs --timeout "$TIMEOUT"
}
