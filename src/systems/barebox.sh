#!/bin/bash

BAREBOX_URL=https://github.com/barebox/barebox
BAREBOX_ARCH=x86 # barebox distinguishes architectures similar to Linux, for simplicity we fix it here

define-system \
    --system barebox \
    --sample-branch master

add-barebox-system(transform...) {
    if is-array-empty transform; then
        transform=(filter-case-insensitive)
    fi
    add-hook-step post-clone-hook post-clone-hook-barebox
    add-hook-step kconfig-post-checkout-hook kconfig-post-checkout-hook-barebox
    add-hook-step kconfig-pre-binding-hook kconfig-pre-binding-hook-barebox
    add-system --system barebox --url "$BAREBOX_URL" --transform "${transform[@]}"
}

add-barebox-kconfig(revision) {
    add-barebox-system
    if [[ ! -d $(input-directory)/barebox ]]; then
        return
    fi
    local kconfig_file
    kconfig_file=$(barebox-kconfig-file "$revision")
    if [[ -z $kconfig_file ]]; then
        return
    fi

    add-revision --system barebox --revision "$revision"
    add-kconfig \
        --system barebox \
        --revision "$revision" \
        --kconfig-file "$kconfig_file" \
        --lkc-directory scripts/kconfig \
        --lkc-target "$(barebox-lkc-target "$revision")" \
        --environment ARCH=$BAREBOX_ARCH,SRCARCH=$BAREBOX_ARCH,CC=gcc,LD=ld,srctree=.,objtree=.
}

add-barebox-kconfig-tags(from=, to=) {
    add-barebox-kconfig-revisions "$(barebox-tags | start-at-revision "$from" | stop-at-revision "$to")"
}

barebox-tags() {
    git-tags barebox | grep -E '^v[0-9]{4}\.[0-9]{2}\.[0-9]+$'
}

barebox-kconfig-file(revision) {
    if git -C "$(input-directory)/barebox" cat-file -e "$revision:Kconfig" 2>/dev/null; then
        echo Kconfig
    elif git -C "$(input-directory)/barebox" cat-file -e "$revision:arch/$BAREBOX_ARCH/Kconfig" 2>/dev/null; then
        # old releases enter through the selected architecture
        echo arch/$BAREBOX_ARCH/Kconfig
    fi
}

barebox-lkc-target(revision) {
    if git -C "$(input-directory)/barebox" show "${revision}^{tree}:scripts/kconfig/Makefile" 2>/dev/null \
        | grep -q 'build_$(1)'; then
        echo build_config
    else
        # old lkc trees build conf as a side effect of make config
        echo config
    fi
}

post-clone-hook-barebox(system, transform...) {
    if [[ $system == barebox ]] && array-contains filter-case-insensitive "${transform[@]}"; then
        filter-case-insensitive-barebox
    fi
}

filter-case-insensitive-barebox() {
    # avoid file/directory collisions on case-insensitive filesystems
    # keep the kconfig content and adjust sources after checkout
    git -C "$(input-directory)/barebox" filter-repo --force \
        --path-rename scripts/Kconfig:scripts/Kconfig.torte \
        --path-rename test/Kconfig:test/Kconfig.torte
}

kconfig-post-checkout-hook-barebox(system, revision) {
    if [[ $system == barebox ]]; then
        patch-barebox-renamed-scripts-kconfig
    fi
}

patch-barebox-renamed-scripts-kconfig() {
    if [[ -f Kconfig ]] && [[ -f scripts/Kconfig.torte ]]; then
        sed -i 's#source "scripts/Kconfig"#source "scripts/Kconfig.torte"#' Kconfig
    fi
    if [[ -f Kconfig ]] && [[ -f test/Kconfig.torte ]]; then
        sed -i 's#source "test/Kconfig"#source "test/Kconfig.torte"#' Kconfig
    fi
}

kconfig-pre-binding-hook-barebox(system, revision, lkc_directory=) {
    if [[ $system == barebox ]]; then
        patch-barebox-kconfig-host-includes
    fi
}

patch-barebox-kconfig-host-includes() {
    # common kconfig objects need the local header dir after conf.c is replaced
    if [[ -f scripts/kconfig/internal.h ]] \
        && [[ -f scripts/kconfig/Makefile ]] \
        && ! grep -q 'torte: common kconfig objects need the local header dir' scripts/kconfig/Makefile; then
        cat >> scripts/kconfig/Makefile <<'EOF'

# torte: common kconfig objects need the local header dir after conf.c is replaced
KBUILD_HOSTCFLAGS += -I $(src)
EOF
    fi
}
