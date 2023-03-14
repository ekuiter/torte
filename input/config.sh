#!/bin/bash

experiment-stages() {
    run-stage \
        `# stage` clone-systems \
        `# dockerfile` scripts/git/Dockerfile \
        `# input` "$(input-directory)" \
        `# command` ./clone-systems.sh

    run-stage \
        `# stage` tag-linux-revisions \
        `# dockerfile` scripts/git/Dockerfile \
        `# input` "$(input-directory)" \
        `# command` ./tag-linux-revisions.sh

    run-stage \
        `# stage` read-statistics \
        `# dockerfile` scripts/git/Dockerfile \
        `# input` "$(input-directory)" \
        `# command` ./read-statistics.sh skip-sloc

    run-iterated-stage \
        `# iterations` 2 \
        `# file field` kconfig-model \
        `# stage field` iteration \
        `# stage` kconfigreader \
        `# dockerfile` scripts/kconfigreader/Dockerfile \
        `# input` "$(input-directory)" \
        `# command` ./extract-kconfig.sh

    run-iterated-stage \
        `# iterations` 2 \
        `# file field` kconfig-model \
        `# stage field` iteration \
        `# stage` kclause \
        `# dockerfile` scripts/kclause/Dockerfile \
        `# input` "$(input-directory)" \
        `# command` ./extract-kconfig.sh

    run-aggregate-stage \
        `# stage` kconfig-models \
        `# file field` kconfig-model \
        `# stage field` extractor \
        `# common fields` system,revision,iteration \
        `# stage transformer` "" \
        `# stages` kconfigreader kclause

    # todo: filter stage that removes input files before executing another stage

    # error handling for missing models
    # write csv file
    # move stats into csv file
    #run-stage evaluation-cnf scripts/featjar/Dockerfile "$(output-directory kconfig-models)" ./transform-into-cnf.sh
    
    # run-stage dimacs-featureide scripts/featjar/Dockerfile "$(output-directory kconfig-models)" ./transform.sh \
    #     `# file field` kconfig-model \
    #     `# input extension` model \
    #     `# output extension` dimacs \
    #     `# transformation` ModelToDIMACSFeatureIDE \
    #     `# timeout in seconds` 10

    # run-stage model-featureide scripts/featjar/Dockerfile "$(output-directory kconfig-models)" ./transform.sh \
    #     `# file field` kconfig-model \
    #     `# input extension` model \
    #     `# output extension` model \
    #     `# transformation` ModelToModelFeatureIDE \
    #     `# timeout in seconds` 10

    # run-stage dimacs-featjar scripts/featjar/Dockerfile "$(output-directory kconfig-models)" ./transform.sh \
    #     `# file field` kconfig-model \
    #     `# input extension` model \
    #     `# output extension` dimacs \
    #     `# transformation` ModelToDIMACSFeatJAR \
    #     `# timeout in seconds` 10
    
    # for file in output/stage2_output/*/temp/*.@(dimacs|smt|model|stats); do
    #     newfile=$(basename $file | sed 's/\.model_/,/g' | sed 's/_0\././g' | sed 's/hierarchy_/hierarchy,/g')
    #     if [[ $newfile != *.stats ]] || [[ $newfile == *hierarchy* ]]; then
    #         cp $file output/intermediate/$newfile
    #     fi
    # done
    # mv output/intermediate/*.dimacs output/dimacs || true
    
    #todo: put number of features, variables, time etc into CSV
}

experiment-subjects() {
    add-system busybox https://github.com/mirror/busybox
    add-system linux https://github.com/torvalds/linux

    add-revision linux v2.5.45
    add-revision linux v2.5.46

    for revision in $(git-revisions busybox | exclude-revision pre alpha rc | grep 1_18_0); do
        add-kconfig busybox "$revision" scripts/kconfig/*.o Config.in ""
    done

    linux_env="ARCH=x86,SRCARCH=x86,KERNELVERSION=kcu,srctree=./,CC=cc,LD=ld,RUSTC=rustc"
    add-kconfig linux v2.6.13 scripts/kconfig/*.o arch/i386/Kconfig $linux_env
}

kconfig-post-checkout-hook() {
    system=$1
    revision=$2
    require-value system revision

    # the following hacks may impair accuracy, but are necessary to extract a kconfig model
    if [[ $system == freetz-ng ]]; then
        # ugly hack because freetz-ng is weird
        touch make/Config.in.generated make/external.in.generated config/custom.in
    fi
    if [[ $system == buildroot ]]; then
        touch .br2-external.in .br2-external.in.paths .br2-external.in.toolchains .br2-external.in.openssl .br2-external.in.jpeg .br2-external.in.menus .br2-external.in.skeleton .br2-external.in.init
        # ignore generated Kconfig files in buildroot
        find ./ -type f -name "*Config.in" -exec sed -i 's/source "\$.*//g' {} \;
    fi
    if [[ $system == toybox ]]; then
        mkdir -p generated
        touch generated/Config.in generated/Config.probed
    fi
    if [[ $system == linux ]]; then
        # ignore all constraints that use the newer $(success,...) syntax
        find ./ -type f -name "*Kconfig*" -exec sed -i "s/\s*default \$(.*//g" {} \;
        find ./ -type f -name "*Kconfig*" -exec sed -i "s/\s*depends on \$(.*//g" {} \;
        find ./ -type f -name "*Kconfig*" -exec sed -i "s/\s*def_bool \$(.*//g" {} \;
        # ugly hack for linux 6.0
        find ./ -type f -name "*Kconfig*" -exec sed -i "s/\s*def_bool ((.*//g" {} \;
        find ./ -type f -name "*Kconfig*" -exec sed -i "s/\s*(CC_IS_CLANG && CLANG_VERSION >= 140000).*//g" {} \;
        find ./ -type f -name "*Kconfig*" -exec sed -i "s/\s*\$(as-instr,endbr64).*//g" {} \;
    fi
}

kclause-post-binding-hook() {
    system=$1
    revision=$2
    require-value system revision

    if [[ $system == embtoolkit ]]; then
        # fix incorrect feature names, which Kclause interprets as a binary subtraction operator
        sed -i 's/-/_/g' "$(output-directory)/$KCONFIG_MODELS_OUTPUT_DIRECTORY/$system/$revision.kclause"
    fi
}

# a version is sys,tag/revision,arch,iteration

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