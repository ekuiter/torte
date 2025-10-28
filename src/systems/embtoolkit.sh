#!/bin/bash

# a frozen copy of the original repository, including the latest versions 1.8.0 and 1.9.0
# actually, the root KConfig file is called Kconfig, not Config.in
# but to avoid case sensitivity issues on macOS, we rewrite the Git history with:
# git filter-repo --path-rename Kconfig:Config.in
EMBTOOLKIT_URL=https://github.com/ekuiter/torte-embtoolkit

add-embtoolkit-kconfig-history(from=, to=) {
    add-system --system embtoolkit --url "$EMBTOOLKIT_URL"
    add-hook-step kconfig-pre-binding-hook kconfig-pre-binding-hook-embtoolkit
    add-hook-step kclause-post-binding-hook kclause-post-binding-hook-embtoolkit
    for revision in $(git-tag-revisions embtoolkit | exclude-revision rc | grep -v -e '-.*-' | start-at-revision "$from" | stop-at-revision "$to"); do
        add-revision --system embtoolkit --revision "$revision"
        add-kconfig \
            --system embtoolkit \
            --revision "$revision" \
            --kconfig-file Config.in \
            --lkc-directory scripts/kconfig
    done
}

kconfig-pre-binding-hook-embtoolkit(system, revision, lkc_directory=) {
    if [[ $system == embtoolkit ]]; then
        # "config" is not enabled as target in the top-level makefile by default, which we fix here by adding it as a target
        if [[ -f mk/buildsystem.mk ]]; then
            sed -i 's/: embtk_kconfig_basic/ config: embtk_kconfig_basic/g' mk/buildsystem.mk
        fi
        if [[ -f core/mk/buildsystem.mk ]]; then
            sed -i 's/: embtk_kconfig_basic/ config: embtk_kconfig_basic/g' core/mk/buildsystem.mk
        fi
    fi
}

kclause-post-binding-hook-embtoolkit(system, revision) {
    if [[ $system == embtoolkit ]]; then
        # fix incorrect feature names, which kclause interprets as a binary subtraction operator
        sed -i 's/-/_/g' "$(output-path "$KCONFIG_MODELS_OUTPUT_DIRECTORY" "$system" "$revision.kextractor")"
    fi
}