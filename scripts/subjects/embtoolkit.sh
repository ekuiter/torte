#!/bin/bash

add-embtoolkit-kconfig-history(from=, to=) {
    add-system --system embtoolkit --url https://github.com/ndmsystems/embtoolkit
    add-hook-step kmax-post-binding-hook embtoolkit "$(to-lambda kmax-post-binding-hook-embtoolkit)"
    for revision in $(git-tag-revisions embtoolkit | exclude-revision rc | grep -v -e '-.*-' | start-at-revision "$from" | stop-at-revision "$to"); do
        add-revision --system embtoolkit --revision "$revision"
        add-kconfig \
            --system embtoolkit \
            --revision "$revision" \
            --kconfig-file Kconfig \
            --kconfig-binding-files scripts/kconfig/*.o
    done
}

kmax-post-binding-hook-embtoolkit(system, revision) {
    if [[ $system == embtoolkit ]]; then
        # fix incorrect feature names, which kmax interprets as a binary subtraction operator
        sed -i 's/-/_/g' "$(output-path "$KCONFIG_MODELS_OUTPUT_DIRECTORY" "$system" "$revision.kextractor")"
    fi
}