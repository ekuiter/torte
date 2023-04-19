#!/bin/bash

add-toybox-kconfig-history(from=, to=) {
    # do not use this toybox model, it is probably incorrect
    add-system --system toybox --url https://github.com/landley/toybox
    add-hook-step kconfig-post-checkout-hook toybox "$(to-lambda kconfig-post-checkout-hook-toybox)"
    add-linux-kconfig-binding --revision v2.6.12
    for revision in $(git-tag-revisions toybox | start-at-revision "$from" | stop-at-revision "$to"); do
        add-revision --system toybox --revision "$revision"
        add-kconfig-model \
            --system toybox \
            --revision "$revision" \
            --kconfig-file Config.in \
            --kconfig-binding-file "$(linux-kconfig-binding-file v2.6.12)"
    done
}

kconfig-post-checkout-hook-toybox(system, revision) {
    if [[ $system == toybox ]]; then
        mkdir -p generated
        touch generated/Config.in generated/Config.probed
    fi
}

add-uclibc-ng-kconfig-history(from=, to=) {
    # environment variable ARCH, VERSION undefined
    add-system --system uclibc-ng --url https://github.com/wbx-github/uclibc-ng
    for revision in $(git-tag-revisions uclibc-ng | start-at-revision "$from" | stop-at-revision "$to"); do
        add-revision --system uclibc-ng --revision "$revision"
        add-kconfig \
            --system uclibc-ng \
            --revision "$revision" \
            --kconfig-file extra/Configs/Config.in \
            --kconfig-binding-files extra/config/zconf.tab.o
    done
}