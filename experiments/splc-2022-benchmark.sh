#!/bin/bash
# The following line uses curl to reproducibly install and run the specified revision of torte.
# Alternatively, torte can be installed manually (see https://github.com/ekuiter/torte).
# In that case, make sure to check out the correct revision manually and run torte.sh <this-file>.
TORTE_REVISION=main; [[ -z $DOCKER_PREFIX ]] && builtin source <(curl -sS https://raw.githubusercontent.com/ekuiter/torte/$TORTE_REVISION/torte.sh) "$@"

PATH_SEPARATOR=_ # remove this to create nested directories instead
TIMEOUT=300 # timeout for extraction and transformation in seconds

experiment-subjects() {
    # we want to extract feature models for the following projects
    add-system --system linux --url https://github.com/torvalds/linux
    add-system --system busybox --url https://github.com/mirror/busybox

    # select revisions to analyze
    for revision in $(git-tag-revisions linux | exclude-revision tree rc "v.*\..*\..*\..*" | start-at-revision v2.6.12 | stop-at-revision v4.18); do
        local arch=x86
        if git -C "$(input-directory)/linux" ls-tree -r "$revision" --name-only | grep -q arch/i386; then
            arch=i386 # in old revisions, x86 is called i386
        fi

        # read statistics for each revision
        add-revision --system linux --revision "$revision"

        # extract feature model for each revision
        # we only consider the x86 architecture here
        add-kconfig \
            --system linux \
            --revision "$revision" \
            --kconfig-file arch/$arch/Kconfig \
            --kconfig-binding-files scripts/kconfig/*.o \
            --environment ARCH=$arch,SRCARCH=$arch,KERNELVERSION=kcu,srctree=./,CC=cc,LD=ld,RUSTC=rustc
    done

    for revision in $(git-tag-revisions busybox | exclude-revision pre alpha rc | start-at-revision 1_3_0); do
        add-revision --system busybox --revision "$revision"
        add-kconfig \
            --system busybox \
            --revision "$revision" \
            --kconfig-file Config.in \
            --kconfig-binding-files scripts/kconfig/*.o
    done
}

experiment-stages() {
    force # do not skip stages

    # clone Linux, remove non-commit v2.6.11, and read committer dates
    run --stage clone-systems
    run --stage tag-linux-revisions --command tag-linux-revisions skip-tagging
    run --stage read-statistics --command read-statistics skip-sloc
    
    # extract feature models
    extract-with(extractor) {
        run \
            --stage "$extractor" \
            --image "$extractor" \
            --command "extract-with-$extractor"
    }
    
    extract-with --extractor kconfigreader
    extract-with --extractor kmax
    
    # aggregate all model files in one directory
    aggregate \
        --stage model \
        --stage-field extractor \
        --file-fields binding-file,model-file \
        --stages kconfigreader kmax
    join-into read-statistics model

    # transform feature models into various formats
    # we skip the distributive CNF transformation, which doesn't work for Linux anyway
    transform-with-featjar(transformer, output_extension, command=transform-with-featjar) {
        run \
            --stage "$transformer" \
            --image featjar \
            --input-directory model \
            --command "$command" \
            --input-extension model \
            --output-extension "$output_extension" \
            --transformer "$transformer" \
            --timeout $TIMEOUT
    }

    # UVL
    transform-with-featjar --transformer uvl --output-extension uvl

    # intermediate formats for CNF transformation
    transform-with-featjar --transformer model_to_model_featureide --output-extension featureide.model
    transform-with-featjar --transformer model_to_smt_z3 --output-extension smt
    
    # Plaisted-Greenbaum CNF tranformation
    run \
        --stage plaistedgreenbaum \
        --image kconfigreader \
        --input-directory model_to_model_featureide \
        --command transform-into-dimacs-with-kconfigreader \
        --input-extension featureide.model \
        --timeout $TIMEOUT
    join-into model_to_model_featureide plaistedgreenbaum

    # Tseitin CNF tranformation
    run \
        --stage tseitin \
        --image z3 \
        --input-directory model_to_smt_z3 \
        --command transform-into-dimacs-with-z3 \
        --timeout $TIMEOUT
    join-into model_to_smt_z3 tseitin

    # aggregate all DIMACS files in one directory
    aggregate \
        --stage dimacs \
        --directory-field dimacs-transformer \
        --file-fields dimacs-file \
        --stages plaistedgreenbaum tseitin
    join-into model dimacs

    # clean up intermediate stages and rearrange output files
    clean clone-systems tag-linux-revisions read-statistics kconfigreader kmax model_to_model_featureide model_to_smt_z3 plaistedgreenbaum tseitin torte
    rm-safe \
        "$OUTPUT_DIRECTORY"/model/*binding* \
        "$OUTPUT_DIRECTORY"/model/*.features \
        "$OUTPUT_DIRECTORY"/model/*.rsf \
        "$OUTPUT_DIRECTORY"/model/*.kclause \
        "$OUTPUT_DIRECTORY"/model/*.kextractor \
        "$OUTPUT_DIRECTORY"/*/*_output*.csv \
        "$OUTPUT_DIRECTORY"/*/*output.*.csv \
        "$OUTPUT_DIRECTORY"/*/*.log \
        "$OUTPUT_DIRECTORY"/*/*.err
}

kconfig-post-checkout-hook(system, revision) {
    # the following hacks may impair accuracy, but are necessary to extract a kconfig model
    if [[ $system == linux ]]; then
        replace(regex) { find ./ -type f -name "*Kconfig*" -exec sed -i "s/$regex//g" {} \;; }
        # ignore all constraints that use the newer $(success,...) syntax
        replace "\s*default \$(.*"
        replace "\s*depends on \$(.*"
        replace "\s*def_bool \$(.*"
        # ugly hack for linux 6.0
        replace "\s*def_bool ((.*"
        replace "\s*(CC_IS_CLANG && CLANG_VERSION >= 140000).*"
        replace "\s*\$(as-instr,endbr64).*"
    fi
}