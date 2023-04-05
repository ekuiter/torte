#!/bin/bash

extract-with(extractor) {
    iterate \
        --stage "$extractor" \
        --iterations 1 \
        --file-fields binding-file,model-file \
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

transform-into-dimacs-with-featjar() {
    transform-with-featjar --command transform-into-dimacs-with-featjar --output-extension dimacs "$@"
}

experiment-subjects() {
    add-system --system busybox --url https://github.com/mirror/busybox
    add-system linux https://github.com/torvalds/linux

    add-revision linux v2.5.45
    add-revision linux v2.5.46

    # for revision in $(git-revisions busybox | exclude-revision pre alpha rc | grep 1_18_0); do
    # #for revision in $(git-revisions busybox | exclude-revision pre alpha rc | start-at-revision 1_3_0); do
    #     add-revision --system busybox --revision "$revision"
    #     add-kconfig \
    #         --system busybox \
    #         --revision "$revision" \
    #         --kconfig-file Config.in \
    #         --kconfig-binding-files scripts/kconfig/*.o
    # done

    # todo: facet around architectures?
    # todo: env not passed right now for kclause
    linux_env="ARCH=x86,SRCARCH=x86,KERNELVERSION=kcu,srctree=./,CC=cc,LD=ld,RUSTC=rustc"
    add-kconfig linux v2.6.13 arch/i386/Kconfig scripts/kconfig/*.o "" #$linux_env
}

experiment-stages() {
    run --stage clone-systems

    #extract-with --extractor kconfigreader
    force; extract-with --extractor kclause
    aggregate \
        --stage kconfig \
        --stage-field extractor \
        --file-fields binding-file,model-file \
        --stages kconfigreader kclause
    
    transform-into-dimacs-with-featjar --transformer model_to_dimacs_featureide
    transform-into-dimacs-with-featjar --transformer model_to_dimacs_featjar
    transform-with-featjar --transformer model_to_model_featureide --output-extension featureide.model
    transform-with-featjar --transformer model_to_smt_z3 --output-extension smt

    run \
        --stage model_to_dimacs_kconfigreader \
        --image kconfigreader \
        --input-directory model_to_model_featureide \
        --command transform-into-dimacs-with-kconfigreader \
        --input-extension featureide.model \
        --timeout 10
    join-into model_to_model_featureide model_to_dimacs_kconfigreader

    run \
        --stage smt_to_dimacs_z3 \
        --image z3 \
        --input-directory model_to_smt_z3 \
        --command transform-into-dimacs-with-z3 \
        --timeout 10
    join-into model_to_smt_z3 smt_to_dimacs_z3

    aggregate \
        --stage dimacs \
        --directory-field dimacs-transformer \
        --file-fields dimacs-file \
        --stages model_to_dimacs_featureide model_to_dimacs_kconfigreader smt_to_dimacs_z3
    join-into kconfig dimacs

    run \
        --stage community-structure \
        --image satgraf \
        --input-directory dimacs \
        --command transform-with-satgraf
    join-into dimacs community-structure
    join-into read-statistics community-structure

    # todos:
    # - filter stage that removes input files before executing another stage
    # - error handling for missing models
}

kconfig-post-checkout-hook(system, revision) {
    if [[ $system == linux ]]; then
        replace(regex) { find ./ -type f -name "*Kconfig*" -exec sed -i "s/$regex//g" {} \;; }
        replace "\s*default \$(.*"
        replace "\s*depends on \$(.*"
        replace "\s*def_bool \$(.*"
        replace "\s*def_bool ((.*"
        replace "\s*(CC_IS_CLANG && CLANG_VERSION >= 140000).*"
        replace "\s*\$(as-instr,endbr64).*"
    fi
}