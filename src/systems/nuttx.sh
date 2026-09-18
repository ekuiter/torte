#!/bin/bash

NUTTX_URL=https://github.com/apache/nuttx

define-system \
    --system nuttx \
    --sample-branch master

add-nuttx-system() {
    add-hook-step kconfig-post-checkout-hook kconfig-post-checkout-hook-nuttx
    add-system --system nuttx --url "$NUTTX_URL"
    add-linux-system
}

# use Linux 4.11 LKC as kconfig-frontends-compatible parser
add-nuttx-kconfig(revision, lkc_revision=v4.11) {
    add-nuttx-system
    if [[ ! -d $(input-directory)/nuttx ]]; then
        return
    fi

    add-linux-lkc-binding --revision "$lkc_revision"
    add-revision --system nuttx --revision "$revision"
    add-kconfig-model \
        --system nuttx \
        --revision "$revision" \
        --kconfig-file Kconfig \
        --lkc-directory "$(none)" \
        --lkc-binding-file "$(linux-lkc-binding-file "$lkc_revision")" \
        --environment APPSDIR=.torte-empty-apps,APPSBINDIR=.torte-empty-apps,BINDIR=.torte-build,EXTERNALDIR=dummy,srctree=.
}

add-nuttx-kconfig-tags(from=, to=) {
    add-nuttx-kconfig-revisions "$(nuttx-tags | start-at-revision "$from" | stop-at-revision "$to")"
}

nuttx-tags() {
    git-tags nuttx | grep -E '^nuttx-[0-9]+([.][0-9]+){1,2}$'
}

kconfig-post-checkout-hook-nuttx(system, revision) {
    if [[ $system == nuttx ]]; then
        mkdir -p \
            .torte-empty-apps \
            .torte-build/arch/dummy \
            .torte-build/boards/dummy \
            .torte-build/drivers/platform/audio \
            .torte-build/drivers/platform/sensors \
            arch/dummy \
            boards/dummy \
            drivers/platform \
            dummy

        wrap-source-statements-in-double-quotes -name 'Kconfig*'

        # apps are maintained in apache/nuttx-apps
        touch .torte-empty-apps/Kconfig

        # BINDIR points to generated arch, board, and platform-driver fragments
        # old dummy handoff files are referenced but not checked in
        touch .torte-build/arch/dummy/Kconfig
        touch .torte-build/boards/dummy/Kconfig
        touch .torte-build/drivers/platform/Kconfig
        touch .torte-build/drivers/platform/audio/Kconfig
        touch .torte-build/drivers/platform/sensors/Kconfig
        touch arch/dummy/Kconfig
        touch boards/dummy/Kconfig
        touch drivers/platform/Kconfig

        # EXTERNALDIR is optional
        touch dummy/Kconfig
    fi
}
