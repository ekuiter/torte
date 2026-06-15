#!/bin/bash

# a frozen copy of the original repository, including the latest versions 1.8.0 and 1.9.0
# actually, the root KConfig file is called Kconfig, not Config.in
# but to avoid case sensitivity issues on macOS, we rewrite the Git history with:
# git filter-repo --path-rename Kconfig:Config.in
EMBTOOLKIT_URL=https://github.com/ekuiter/torte-embtoolkit

define-system \
    --system embtoolkit \
    --kconfig-file Config.in \
    --lkc-directory scripts/kconfig \
    --sample-branch master

add-embtoolkit-system() {
    add-hook-step kconfig-pre-binding-hook kconfig-pre-binding-hook-embtoolkit
    add-hook-step kclause-post-binding-hook kclause-post-binding-hook-embtoolkit
    add-hook-step configfix-pre-extraction-hook configfix-pre-extraction-hook-embtoolkit
    add-system --system embtoolkit --url "$EMBTOOLKIT_URL"
}

add-embtoolkit-kconfig-tags(from=, to=) {
    add-embtoolkit-kconfig-revisions \
        "$(git-tags embtoolkit | exclude-revision rc | grep -v -e '-.*-' | start-at-revision "$from" | stop-at-revision "$to")"
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

kclause-post-binding-hook-embtoolkit(system, revision, date_prefix=) {
    if [[ $system == embtoolkit ]]; then
        # fix incorrect feature names, which kclause interprets as a binary subtraction operator
        sed -i 's/-/_/g' "$(output-path "$system" "${date_prefix}$revision.kextractor")"
    fi
}

configfix-pre-extraction-hook-embtoolkit(system, revision) {
    if [[ $system == embtoolkit ]]; then
        wrap-source-statements-in-double-quotes \( -name Config.in -o -name '*.kconfig' \)
        remove-environment-variable-imports \( -name Config.in -o -name '*.kconfig' \)
        # for embtoolkit, we do not call ConfigFix from the LKC makefiles, but directly
        echo "override-lkc-target=$(none)"
    fi
}
