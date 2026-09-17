#!/bin/bash

UBOOT_URL=https://github.com/u-boot/u-boot

define-system \
    --system u-boot \
    --sample-branch main

add-u-boot-system(transform...) {
    if is-array-empty transform; then
        transform=(filter-case-insensitive)
    fi
    add-hook-step post-clone-hook post-clone-hook-u-boot
    add-hook-step kconfig-post-checkout-hook kconfig-post-checkout-hook-u-boot
    add-hook-step kconfig-pre-binding-hook kconfig-pre-binding-hook-u-boot
    add-system --system u-boot --url "$UBOOT_URL" --transform "${transform[@]}"
}

add-u-boot-kconfig(revision) {
    add-u-boot-system
    if [[ ! -d $(input-directory)/u-boot ]]; then
        return
    fi

    add-revision --system u-boot --revision "$revision"
    add-kconfig \
        --system u-boot \
        --revision "$revision" \
        --kconfig-file Kconfig \
        --lkc-directory scripts/kconfig \
        --lkc-target "$(u-boot-lkc-target "$revision")" \
        --environment ARCH=sandbox,SRCARCH=sandbox,SUBARCH=sandbox,CC=gcc,LD=ld,HOSTCC=gcc,srctree=.,objtree=.,KCONFIG_OBJDIR=.,UBOOTVERSION="$revision"
}

add-u-boot-kconfig-tags(from=, to=) {
    add-u-boot-kconfig-revisions "$(u-boot-tags | start-at-revision "$from" | stop-at-revision "$to")"
}

u-boot-tags() {
    git-tags u-boot | grep -E '^v[0-9]{4}\.[0-9]{2}$'
}

u-boot-lkc-target(revision) {
    if git -C "$(input-directory)/u-boot" show "${revision}^{tree}:scripts/kconfig/Makefile" 2>/dev/null \
        | grep -q 'build_$(1)'; then
        echo build_config
    else
        # old make config targets still build scripts/kconfig/conf
        echo config
    fi
}

post-clone-hook-u-boot(system, transform...) {
    if [[ $system == u-boot ]] && array-contains filter-case-insensitive "${transform[@]}"; then
        filter-case-insensitive-u-boot
    fi
}

filter-case-insensitive-u-boot() {
    # avoid file/directory collisions on case-insensitive filesystems
    # keep the kconfig content and adjust sources after checkout
    git -C "$(input-directory)/u-boot" filter-repo --force \
        --path-rename scripts/Kconfig:scripts/Kconfig.torte
}

kconfig-post-checkout-hook-u-boot(system, revision) {
    if [[ $system == u-boot ]]; then
        patch-u-boot-renamed-scripts-kconfig
    fi
}

patch-u-boot-renamed-scripts-kconfig() {
    if [[ -f Kconfig && -f scripts/Kconfig.torte ]]; then
        sed -i 's#source "scripts/Kconfig"#source "scripts/Kconfig.torte"#' Kconfig
    fi
}

kconfig-pre-binding-hook-u-boot(system, revision, lkc_directory=) {
    if [[ $system == u-boot ]]; then
        patch-u-boot-kconfig-host-includes
    fi
}

patch-u-boot-kconfig-host-includes() {
    if [[ -f scripts/kconfig/internal.h ]] \
        && [[ -f scripts/kconfig/Makefile ]] \
        && ! grep -q 'torte: common kconfig objects need the local header dir' scripts/kconfig/Makefile; then
        cat >> scripts/kconfig/Makefile <<'EOF'

# torte: common kconfig objects need the local header dir after conf.c is replaced
KBUILD_HOSTCFLAGS += -I $(src)
EOF
    fi
}
