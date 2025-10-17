#!/bin/bash

TOYBOX_URL=https://github.com/landley/toybox

add-toybox-kconfig-history(from=, to=) {
    # do not use this toybox model, it is probably incorrect
    add-system --system toybox --url "$TOYBOX_URL"
    add-hook-step kconfig-post-checkout-hook toybox "$(to-lambda kconfig-post-checkout-hook-toybox)"
    for revision in $(git-tag-revisions toybox | start-at-revision "$from" | stop-at-revision "$to"); do
        add-revision --system toybox --revision "$revision"
        add-kconfig \
            --system toybox \
            --revision "$revision" \
            --kconfig-file Config.in \
            --lkc-directory kconfig
    done
}

kconfig-post-checkout-hook-toybox(system, revision) {
    if [[ $system == toybox ]]; then
        # here we remove the inline attribute for kconf_id_lookup
        # without this hack, we cannot compile the LKC binding (undefined reference to `kconf_id_lookup')
        # this may be due to outdated gcc in the KConfigReader image and doesn't affect our extraction
        if [[ -f $(input-directory)/toybox/kconfig/zconf.hash.c_shipped ]]; then
            sed -i 's/^__inline$//' "$(input-directory)/toybox/kconfig/zconf.hash.c_shipped"
        fi
    fi
}