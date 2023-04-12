#!/bin/bash
# The following line uses curl to reproducibly install and run the specified revision of torte.
# Alternatively, torte can be installed manually (see https://github.com/ekuiter/torte).
# In that case, make sure to check out the correct revision manually and run torte.sh <this-file>.
TORTE_REVISION=753c4a7; [[ -z $DOCKER_PREFIX ]] && builtin source <(curl -fsSL https://raw.githubusercontent.com/ekuiter/torte/$TORTE_REVISION/torte.sh) "$@"

experiment-subjects() {
    add-system --system busybox --url https://github.com/mirror/busybox
    
    add-kconfig \
        --system busybox \
        --revision 1_18_0 \
        --kconfig-file Config.in \
        --kconfig-binding-files scripts/kconfig/*.o
}

experiment-stages() {
    extract-with(extractor) {
        run \
            --stage "$extractor" \
            --image "$extractor" \
            --command "extract-with-$extractor"
    }

    transform-with-featjar(transformer, output_extension, command=transform-with-featjar) {
        run \
            --stage "$transformer" \
            --image featjar \
            --input-directory kconfig \
            --command "$command" \
            --input-extension model \
            --output-extension "$output_extension" \
            --transformer "$transformer"
    }

    transform-into-dimacs-with-featjar(transformer) {
        transform-with-featjar --command transform-into-dimacs-with-featjar --output-extension dimacs --transformer "$transformer"
    }

    run --stage clone-systems
    extract-with --extractor kconfigreader
    extract-with --extractor kmax
    aggregate \
        --stage kconfig \
        --stage-field extractor \
        --file-fields binding-file,model-file \
        --stages kconfigreader kmax
    
    transform-with-featjar --transformer model_to_xml_featureide --output-extension xml
    transform-with-featjar --transformer model_to_uvl_featureide --output-extension uvl
    transform-into-dimacs-with-featjar --transformer model_to_dimacs_featureide
    transform-into-dimacs-with-featjar --transformer model_to_dimacs_featjar
    transform-with-featjar --transformer model_to_model_featureide --output-extension featureide.model
    transform-with-featjar --transformer model_to_smt_z3 --output-extension smt

    run \
        --stage model_to_dimacs_kconfigreader \
        --image kconfigreader \
        --input-directory model_to_model_featureide \
        --command transform-into-dimacs-with-kconfigreader \
        --input-extension featureide.model
    join-into model_to_model_featureide model_to_dimacs_kconfigreader

    run \
        --stage smt_to_dimacs_z3 \
        --image z3 \
        --input-directory model_to_smt_z3 \
        --command transform-into-dimacs-with-z3
    join-into model_to_smt_z3 smt_to_dimacs_z3

    aggregate \
        --stage dimacs \
        --directory-field dimacs-transformer \
        --file-fields dimacs-file \
        --stages model_to_dimacs_featureide model_to_dimacs_kconfigreader smt_to_dimacs_z3
    join-into kconfig dimacs
}