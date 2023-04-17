#!/bin/bash
# The following line uses curl to reproducibly install and run the specified revision of torte.
# Alternatively, torte can be installed manually (see https://github.com/ekuiter/torte).
# In that case, make sure to check out the correct revision manually and run torte.sh <this-file>.
TORTE_REVISION=753c4a7; [[ -z $DOCKER_PREFIX ]] && builtin source <(curl -fsSL https://raw.githubusercontent.com/ekuiter/torte/$TORTE_REVISION/torte.sh) "$@"

PATH_SEPARATOR=_ # create no nested directories
TIMEOUT=300 # timeout for extraction and transformation in seconds

experiment-subjects() {
    ignore() {
    # busybox
    add-system --system busybox --url https://github.com/mirror/busybox
    
    for revision in $(git-tag-revisions busybox | exclude-revision pre alpha rc | start-at-revision 1_3_0); do
        add-revision --system busybox --revision "$revision"
        add-kconfig \
            --system busybox \
            --revision "$revision" \
            --kconfig-file Config.in \
            --kconfig-binding-files scripts/kconfig/*.o
    done

    # linux
    add-system --system linux --url https://github.com/torvalds/linux
    
    linux-tag-revisions() {
        git-tag-revisions linux | exclude-revision tree rc "v.*\..*\..*\..*"
    }

    # todo: move into main codebase, linux.sh, for reusability
    add-linux-kconfig(revision, kconfig_binding_file=) {
        local arch=x86
        if git -C "$(input-directory)/linux" ls-tree -r "$revision" --name-only | grep -q arch/i386; then
            arch=i386 # in old revisions, x86 is called i386
        fi

        # read statistics for each revision
        add-revision --system linux --revision "$revision"

        # extract feature model for each revision
        # we only consider the x86 architecture here
        local environment=ARCH=$arch,SRCARCH=$arch,KERNELVERSION=kcu,srctree=./,CC=cc,LD=ld,RUSTC=rustc
        if [[ -n $kconfig_binding_file ]]; then
            add-kconfig-model \
                --system linux \
                --revision "$revision" \
                --kconfig-file arch/$arch/Kconfig \
                --kconfig-binding-file "$kconfig_binding_file" \
                --environment "$environment"
        else
            add-kconfig \
                --system linux \
                --revision "$revision" \
                --kconfig-file arch/$arch/Kconfig \
                --kconfig-binding-files scripts/kconfig/*.o \
                --environment "$environment"
        fi
    }

    # for up to linux 2.6.9, use the kconfig parser of linux 2.6.9 for extraction
    add-kconfig-binding --system linux --revision v2.6.9 --kconfig_binding_files scripts/kconfig/*.o
    for revision in $(linux-tag-revisions | stop-at-revision v2.6.9); do
        add-linux-kconfig \
            --revision "$revision" \
            --kconfig-binding-file "$(output-path "$KCONFIG_BINDINGS_OUTPUT_DIRECTORY" linux v2.6.9)"
    done

    # after linux 2.6.9, use the kconfig parser of the respective revision
    for revision in $(linux-tag-revisions | start-at-revision v2.6.9 | stop-at-revision v4.18); do
        add-linux-kconfig --revision "$revision"
    done
    }

    # axtls
    add-system --system axtls --url https://github.com/ekuiter/axTLS
    for revision in $(git-tag-revisions axtls | exclude-revision @); do
        add-kconfig \
            --system axtls \
            --revision "$revision" \
            --kconfig-file config/Config.in \
            --kconfig-binding-files config/scripts/config/*.o
    done

    # # buildroot
    # export BR2_EXTERNAL=support/dummy-external
    # export BUILD_DIR=buildroot
    # export BASE_DIR=buildroot
    # add-system --system buildroot --url https://github.com/buildroot/buildroot
    # for tag in $(git-tag-revisions buildroot | exclude-revision rc _ "\..*\."); do
    #     run buildroot  $tag c-bindings/linux/v4.17.$BINDING Config.in
    # done

    # # embtoolkit
    # add-system --system embtoolkit --url https://github.com/ndmsystems/embtoolkit
    # for tag in $(git-tag-revisions embtoolkit | exclude-revision rc | grep -v -e "-.*-"); do
    #     run embtoolkit  $tag scripts/kconfig/*.o Kconfig
    # done

    # # fiasco
    # add-system --system fiasco --url https://github.com/kernkonzept/fiasco
    # run fiasco  d393c79a5f67bb5466fa69b061ede0f81b6398db c-bindings/linux/v5.0.$BINDING src/Kconfig

    # # freetz-ng
    # add-system --system freetz-ng --url https://github.com/Freetz-NG/freetz-ng
    # run freetz-ng  88b972a6283bfd65ae1bbf559e53caf7bb661ae3 c-bindings/linux/v5.0.$BINDING config/Config.in

    # # toybox
    # add-system --system toybox --url https://github.com/landley/toybox
    # for tag in $(git-tag-revisions toybox); do
    #     run toybox  $tag c-bindings/linux/v2.6.12.$BINDING Config.in
    # done

    # # uclibc-ng
    # add-system --system uclibc-ng --url https://github.com/wbx-github/uclibc-ng
    # for tag in $(git-tag-revisions uclibc-ng); do
    #     run uclibc-ng  $tag extra/config/zconf.tab.o extra/Configs/Config.in
    # done
}

experiment-stages() {
    force # do not skip stages

    # clone Linux, remove non-commit v2.6.11, and read committer dates
    run --stage clone-systems
    run --stage tag-linux-revisions --command tag-linux-revisions
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
}

kconfig-post-checkout-hook(system, revision) {
    # todo: move this into main codebase
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

clean-up() {
    # clean up intermediate stages and rearrange output files
    clean clone-systems tag-linux-revisions read-statistics kconfigreader kmax \
        model_to_model_featureide model_to_smt_z3 plaistedgreenbaum tseitin torte
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