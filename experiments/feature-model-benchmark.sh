#!/bin/bash
# The point of this experiment file is to extract feature models for a large and representative selection of Kconfig-based configurable systems and their revisions.
# More information on some of the systems below can be found in Berger et al.'s "Variability Modeling in the Systems Software Domain" (DOI: 10.1109/TSE.2013.34).
# Our general strategy is to read feature models for all tagged Git revisions (provided that tags give a meaningful history).
# We usually compile dumpconf against the project source to get the most accurate translation.
# Sometimes this is not possible, then we use dumpconf compiled for a Linux version with a similar Kconfig dialect (in most projects, the Kconfig parser is cloned&owned from Linux).
# It is also possible to read feature models for any other tags/commits (e.g., for every commit that changes a Kconfig file), although usually very old versions won't work (because Kconfig might have only been introduced later) and very recent versions might also not work (because they use new/esoteric Kconfig features not supported by kconfigreader or dumpconf).

# The following Kconfig-based systems are deliberately no included right now:
# https://github.com/coreboot/coreboot uses a modified Kconfig with wildcards for the source directive
# https://github.com/Freetz/freetz uses Kconfig, but cannot be parsed with dumpconf, so we use freetz-ng instead (which is newer anyway)
# https://github.com/rhuitl/uClinux is not so easy to set up, because it depends on vendor files
# https://github.com/zephyrproject-rtos/zephyr also uses Kconfig, but a modified dialect based on Kconfiglib, which is not compatible with kconfigreader
# https://github.com/solettaproject/soletta not yet included, many models available at https://github.com/TUBS-ISF/soletta-case-study

# The following line uses curl to reproducibly install and run the specified revision of torte.
# Alternatively, torte can be installed manually (see https://github.com/ekuiter/torte).
# In that case, make sure to check out the correct revision manually and run torte.sh <this-file>.
TORTE_REVISION=main; [[ -z $DOCKER_PREFIX ]] && builtin source <(curl -fsSL https://raw.githubusercontent.com/ekuiter/torte/$TORTE_REVISION/torte.sh) "$@"

PATH_SEPARATOR=_ # create no nested directories
TIMEOUT=300 # timeout for extraction and transformation in seconds

experiment-subjects() {
    :
    #add-axtls-kconfig-history
    #add-busybox-kconfig-history

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

    #add-fiasco-kconfig 58aa50a8aae2e9396f1c8d1d0aa53f2da20262ed # todo: update revision

    add-freetz-ng-kconfig 5c5a4d1d87ab8c9c6f121a13a8fc4f44c79700af # todo: update revision

    #add-linux-kconfig-history --from v3.0 --to v3.5
   
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

return

#### todo

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