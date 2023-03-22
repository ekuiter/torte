#!/bin/bash

# defines the stages of the experiment in order of their execution
experiment-stages() {
    # clone the systems specified as experiment subjects
    run-stage --stage clone-systems

    # tag old Linux revisions that are not included in its Git history
    run-stage --stage tag-linux-revisions

    # read basic statistics for each system
    run-stage --stage read-statistics --command read-statistics.sh # skip-sloc
    
    # use a given extractor to extract a kconfig model for each specified experiment subject
    extract-with(extractor) {
        run-iterated-stage \
            --stage "$extractor" \
            --iterations 2 \
            --file-fields kconfig-binding-file,kconfig-model-file \
            --dockerfile "$extractor" \
            --command extract-kconfig-models.sh
    }

    extract-with kconfigreader
    extract-with kclause

    run-aggregate-stage \
        --stage kconfig \
        --stage-field extractor \
        --file-fields kconfig-binding-file,kconfig-model-file \
        --stages kconfigreader kclause

    # use featjar to transform kconfig models into various formats and then into DIMACS
    transform-with(transformation, output_extension) {
        run-stage \
            --stage "$transformation" \
            --dockerfile featjar \
            --input-directory kconfig \
            --command transform.sh \
            `# file field` kconfig-model-file \
            `# input extension` model \
            `# output extension` "$output_extension" \
            `# transformation` "$transformation" \
            `# timeout in seconds` 10
    }

    transform-with modeltodimacsfeatureide dimacs
    transform-with modeltomodelfeatureide model
    transform-with modeltosmtz3 smt
    transform-with modeltodimacsfeatjar dimacs

    run-stage \
        --stage modeltodimacskconfigreader \
        --dockerfile kconfigreader \
        --input-directory modeltomodelfeatureide \
        --command transform-into-dimacs.sh \
        `# timeout in seconds` 10
    run-join-into modeltomodelfeatureide modeltodimacskconfigreader

    run-stage \
        --stage smttodimacsz3 \
        --dockerfile z3 \
        --input-directory modeltosmtz3 \
        --command transform-into-dimacs.sh \
        `# timeout in seconds` 10
    run-join-into modeltosmtz3 smttodimacsz3

    run-aggregate-stage \
        --stage dimacs \
        --stage-field transformation \
        --file-fields dimacs-file \
        --stages modeltodimacsfeatureide modeltodimacskconfigreader smttodimacsz3
    run-join-into kconfig dimacs

    # todos:
    # - reorder run-stage args to "input-dir output-dir/stage dockerfile command"
    # - filter stage that removes input files before executing another stage
    # - error handling for missing models
    # - move stats on formulas into csv file
    # - put number of features, variables, time etc into CSV
}

# defines the experiment subjects
experiment-subjects() {
    add-system busybox https://github.com/mirror/busybox
    #add-system linux https://github.com/torvalds/linux

    # add-revision linux v2.5.45
    # add-revision linux v2.5.46

    for revision in $(git-revisions busybox | exclude-revision pre alpha rc | grep 1_18_0); do
        add-revision busybox "$revision"
        add-kconfig busybox "$revision" Config.in scripts/kconfig/*.o ""
    done

    # todo: facet around architectures?
    # linux_env="ARCH=x86,SRCARCH=x86,KERNELVERSION=kcu,srctree=./,CC=cc,LD=ld,RUSTC=rustc"
    # add-kconfig linux v2.6.13 arch/i386/Kconfig scripts/kconfig/*.o $linux_env
}

# called after a system has been checked out during kconfig model extraction
kconfig-post-checkout-hook(system, revision) {
    # the following hacks may impair accuracy, but are necessary to extract a kconfig model
    if [[ $system == freetz-ng ]]; then
        # ugly hack because freetz-ng is weird
        touch make/Config.in.generated make/external.in.generated config/custom.in
    fi
    if [[ $system == buildroot ]]; then
        touch .br2-external.in .br2-external.in.paths .br2-external.in.toolchains \
            .br2-external.in.openssl .br2-external.in.jpeg .br2-external.in.menus \
            .br2-external.in.skeleton .br2-external.in.init
        # ignore generated Kconfig files in buildroot
        find ./ -type f -name "*Config.in" -exec sed -i 's/source "\$.*//g' {} \;
    fi
    if [[ $system == toybox ]]; then
        mkdir -p generated
        touch generated/Config.in generated/Config.probed
    fi
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

# called after a kconfig binding has been executed during kconfig model extraction
kclause-post-binding-hook(system, revision) {
    if [[ $system == embtoolkit ]]; then
        # fix incorrect feature names, which Kclause interprets as a binary subtraction operator
        sed -i 's/-/_/g' "$(output-directory)/$KCONFIG_MODELS_OUTPUT_DIRECTORY/$system/$revision.kclause"
    fi
}

#ANALYSES="void dead core" # analyses to run on feature models, see run-...-analysis functions
#ANALYSES="void" # analyses to run on feature models, see run-...-analysis functions
# TIMEOUT_ANALYZE=1800 # analysis timeout in seconds
# RANDOM_SEED=2302101557 # seed for choosing core/dead features
# NUM_FEATURES=1 # number of randomly chosen core/dead features

# evaluated (#)SAT solvers
# we choose all winning SAT solvers in SAT competitions
# for #SAT, we choose the five fastest solvers as evaluated by Sundermann et al. 2021, found here: https://github.com/SoftVarE-Group/emse21-evaluation-sharpsat/tree/main/solvers
#SOLVERS="sharpsat-countAntom sharpsat-d4 sharpsat-dsharp sharpsat-ganak sharpsat-sharpSAT"
#SOLVERS="c2d d4 dpmc gpmc sharpsat-td-arjun1 sharpsat-td-arjun2 sharpsat-td twg"
#SOLVERS="d4"

# # in old versions, use kconfig-binding from 2.6.12
# for tag in $(git -C input/linux tag | grep -v rc | grep -v tree | sort -V | sed -n '/2.6.12/q;p'); do
# #for tag in $(git -C input/linux tag | grep -v rc | grep -v tree | sort -V | sed -n '/2.6.0/,$p' | sed -n '/2.6.4/q;p'); do
#     run linux https://github.com/torvalds/linux $tag /home/output/kconfig-bindings/linux/v2.6.12.$BINDING arch/i386/Kconfig $linux_env
# done

# for tag in $(git -C input/linux tag | grep -v rc | grep -v tree | sort -V | sed -n '/2.6.12/,$p'); do
#     if git -C input/linux ls-tree -r $tag --name-only | grep -q arch/i386; then
#         run linux https://github.com/torvalds/linux $tag scripts/kconfig/*.o arch/i386/Kconfig $linux_env # in old versions, x86 is called i386
#     else
#         run linux https://github.com/torvalds/linux $tag scripts/kconfig/*.o arch/x86/Kconfig $linux_env
#     fi
# done

# for tag in $(git -C input/linux tag | grep -v rc | grep -v tree | sort -V | sed -n '/2.6.35/,$p' | sed -n '/2.6.37/q;p'); do
#     if git -C input/linux ls-tree -r $tag --name-only | grep -q arch/i386; then
#         run linux https://github.com/torvalds/linux $tag scripts/kconfig/*.o arch/i386/Kconfig $linux_env # in old versions, x86 is called i386
#     else
#         run linux https://github.com/torvalds/linux $tag scripts/kconfig/*.o arch/x86/Kconfig $linux_env
#     fi
# done