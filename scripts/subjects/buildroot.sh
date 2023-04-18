#!/bin/bash

add-buildroot-kconfig-history(from=, to=) {
    export BR2_EXTERNAL=support/dummy-external
    export BUILD_DIR=buildroot
    export BASE_DIR=buildroot
    add-system --system buildroot --url https://github.com/buildroot/buildroot
    add-linux-kconfig-binding --revision v4.17
    add-hook-step kconfig-post-checkout-hook buildroot "$(to-lambda kconfig-post-checkout-hook-buildroot)"
    for revision in $(git-tag-revisions buildroot | exclude-revision rc _ 'settings-.*' '\..*\.' | start-at-revision "$from" | stop-at-revision "$to"); do
        add-revision --system buildroot --revision "$revision"
        add-kconfig-model \
            --system buildroot \
            --revision "$revision" \
            --kconfig-file Config.in \
            --kconfig-binding-file "$(linux-kconfig-binding-file v4.17)"
    done
}

kconfig-post-checkout-hook-buildroot(system, revision) {
    if [[ $system == buildroot ]]; then
        touch .br2-external.in .br2-external.in.paths .br2-external.in.toolchains \
            .br2-external.in.openssl .br2-external.in.jpeg .br2-external.in.menus \
            .br2-external.in.skeleton .br2-external.in.init
        # ignore generated Kconfig files in buildroot
        find ./ -type f -name "*Config.in" -exec sed -i 's/source "\$.*//g' {} \;
    fi
}