#!/bin/bash

TOYBOX_URL=https://github.com/landley/toybox

# like BusyBox, toybox generates parts of its feature model (with https://github.com/landley/toybox/blob/master/scripts/genconfig.sh)
# this is no issue as long as we don't aim to analyze every single commit that touches the feature model
# (for BusyBox, we enable this with generate-busybox-models, and a similar approach could probably be used here)

add-toybox-kconfig-history(from=, to=) {
    add-system --system toybox --url "$TOYBOX_URL"
    add-hook-step kconfig-pre-binding-hook toybox "$(to-lambda kconfig-pre-binding-hook-toybox)"
    for revision in $(git-tag-revisions toybox | start-at-revision "$from" | stop-at-revision "$to"); do
        add-revision --system toybox --revision "$revision"
        add-kconfig \
            --system toybox \
            --revision "$revision" \
            --kconfig-file Config.in \
            --lkc-directory kconfig
    done
}

kconfig-pre-binding-hook-toybox(system, revision, lkc_directory=) {
    if [[ $system == toybox ]]; then
        # here we remove the inline attribute for kconf_id_lookup
        # without this hack, we cannot compile the LKC binding (undefined reference to `kconf_id_lookup')
        # this may be due to outdated gcc in the KConfigReader image and doesn't affect our extraction
        if [[ -f $(input-directory)/toybox/kconfig/zconf.hash.c_shipped ]]; then
            sed -i 's/^__inline$//' "$(input-directory)/toybox/kconfig/zconf.hash.c_shipped"
        fi
    fi
}