#!/bin/bash
# The following line uses curl to reproducibly install and run the specified revision of torte.
# Alternatively, torte can be installed manually (see https://github.com/ekuiter/torte).
# In that case, make sure to check out the correct revision manually and run torte.sh <this-file>.
TORTE_REVISION=main; [[ -z $DOCKER_PREFIX ]] && builtin source <(curl -fsSL https://raw.githubusercontent.com/ekuiter/torte/$TORTE_REVISION/torte.sh) "$@"

# todo: this is still incomplete, no analysis is performed yet, systems are missing

experiment-stages() {
    # clone the systems specified as experiment subjects
    run --stage clone-systems

    # tag old Linux revisions that are not included in its Git history
    run --stage tag-linux-revisions

    # read basic statistics for each system
    run --stage read-statistics
    #plot --stage read-statistics --type scatter --fields committer_date_unix,source_lines_of_code

    # use a given extractor to extract a kconfig model for each specified experiment subject
    extract-with(extractor) {
        iterate \
            --stage "$extractor" \
            --iterations 1 \
            --file-fields binding-file,model-file \
            --image "$extractor" \
            --command "extract-with-$extractor"
    }

    extract-with --extractor kconfigreader
    extract-with --extractor kmax

    aggregate \
        --stage kconfig \
        --stage-field extractor \
        --file-fields binding-file,model-file \
        --stages kconfigreader kmax

    # use featjar to transform kconfig models into various formats and then into DIMACS
    transform-with-featjar(transformer, output_extension, command=transform-with-featjar) {
        run \
            --stage "$transformer" \
            --image featjar \
            --input-directory kconfig \
            --command "$command" \
            --input-extension model \
            --output-extension "$output_extension" \
            --transformer "$transformer" \
            --timeout 10
    }

    transform-into-dimacs-with-featjar(transformer) {
        transform-with-featjar --command transform-into-dimacs-with-featjar --output-extension dimacs --transformer "$transformer"
    }

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
}

experiment-subjects() {
    add-system --system busybox --url https://github.com/mirror/busybox
    #add-system linux https://github.com/torvalds/linux

    # add-revision linux v2.5.45
    # add-revision linux v2.5.46

    for revision in $(git-tag-revisions busybox | exclude-revision pre alpha rc | grep 1_18_0); do
    #for revision in $(git-tag-revisions busybox | exclude-revision pre alpha rc | start-at-revision 1_3_0); do
        add-revision --system busybox --revision "$revision"
        add-kconfig \
            --system busybox \
            --revision "$revision" \
            --kconfig-file Config.in \
            --kconfig-binding-files scripts/kconfig/*.o
    done

    # linux_env="ARCH=x86,SRCARCH=x86,KERNELVERSION=kcu,srctree=./,CC=cc,LD=ld,RUSTC=rustc"
    # add-kconfig linux v2.6.13 arch/i386/Kconfig scripts/kconfig/*.o $linux_env
}

# todo: add-hook via lambda in subjects .sh?
#todo:document hacks in readme
kconfig-post-checkout-hook(system, revision) {
    # the following hacks may impair accuracy, but are necessary to extract some kconfig models
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

kmax-post-binding-hook(system, revision) {
    if [[ $system == embtoolkit ]]; then
        # fix incorrect feature names, which kmax interprets as a binary subtraction operator
        sed -i 's/-/_/g' "$(output-path "$KCONFIG_MODELS_OUTPUT_DIRECTORY" "$system" "$revision.kextractor")"
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

return

export BR2_EXTERNAL=support/dummy-external
export BUILD_DIR=/home/input/buildroot
export BASE_DIR=/home/input/buildroot
if echo $KCONFIG | grep -q buildroot; then
    run linux skip-model v4.17 scripts/kconfig/*.o arch/x86/Kconfig $linux_env
fi

export BR2_EXTERNAL=support/dummy-external
export BUILD_DIR=buildroot
export BASE_DIR=buildroot
git-checkout buildroot https://github.com/buildroot/buildroot
for tag in $(git -C buildroot tag | grep -v rc | grep -v _ | grep -v -e '\..*\.'); do
    run buildroot https://github.com/buildroot/buildroot $tag c-bindings/linux/v4.17.$BINDING Config.in
done

git-checkout embtoolkit https://github.com/ndmsystems/embtoolkit
for tag in $(git -C embtoolkit tag | grep -v rc | grep -v -e '-.*-'); do
    run embtoolkit https://github.com/ndmsystems/embtoolkit $tag scripts/kconfig/*.o Kconfig
done

git-checkout toybox https://github.com/landley/toybox
for tag in $(git -C toybox tag); do
    run toybox https://github.com/landley/toybox $tag c-bindings/linux/v2.6.12.$BINDING Config.in
done

git-checkout uclibc-ng https://github.com/wbx-github/uclibc-ng
for tag in $(git -C uclibc-ng tag); do
    run uclibc-ng https://github.com/wbx-github/uclibc-ng $tag extra/config/zconf.tab.o extra/Configs/Config.in
done