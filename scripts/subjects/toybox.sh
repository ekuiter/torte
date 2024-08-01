#!/bin/bash

add-toybox-kconfig-history(from=, to=) {
    # do not use this toybox model, it is probably incorrect
    add-system --system toybox --url https://github.com/landley/toybox
    add-hook-step kconfig-post-checkout-hook toybox "$(to-lambda kconfig-post-checkout-hook-toybox)"
    add-linux-kconfig-binding --revision v6.7
    for revision in $(git-tag-revisions toybox | start-at-revision "$from" | stop-at-revision "$to"); do
        add-revision --system toybox --revision "$revision"
        add-kconfig-model \
            --system toybox \
            --revision "$revision" \
            --kconfig-file Config.in \
            --kconfig-binding-file "$(linux-kconfig-binding-file v6.7)"
    done
}

kconfig-post-checkout-hook-toybox(system, revision) {
    if [[ $system == toybox ]]; then
        mkdir -p generated
        touch generated/Config.in generated/Config.probed
    fi
}