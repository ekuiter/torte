#!/bin/bash
# The following are templates and convenience functions for working with common experiment subjects.
# Most functions extract (an excerpt of) the tagged history of a kconfig model.
# For customizations (e.g., extract one specific revision or weekly revisions), copy the code to your experiment file and adjust it.

add-axtls-kconfig-history(from=, to=) {
    add-system --system axtls --url https://github.com/ekuiter/axTLS
    for revision in $(git-tag-revisions axtls | exclude-revision @ | start-at-revision "$from" | stop-at-revision "$to"); do
        add-kconfig \
            --system axtls \
            --revision "$revision" \
            --kconfig-file config/Config.in \
            --kconfig-binding-files config/scripts/config/*.o
    done
}

add-busybox-kconfig-history(from=1_3_0, to=) {
    add-system --system busybox --url https://github.com/mirror/busybox
    for revision in $(git-tag-revisions busybox | exclude-revision pre alpha rc | start-at-revision "$from" | stop-at-revision "$to"); do
        add-revision --system busybox --revision "$revision"
        add-kconfig \
            --system busybox \
            --revision "$revision" \
            --kconfig-file Config.in \
            --kconfig-binding-files scripts/kconfig/*.o
    done
}

add-fiasco-kconfig(revision) {
    # todo: upgrade to 6.2 as written here: https://github.com/kernkonzept/fiasco/tree/master/tool/kconfig
    add-linux-kconfig-binding --revision v5.0
    add-system --system fiasco --url https://github.com/kernkonzept/fiasco
    add-kconfig-model \
            --system fiasco \
            --revision "$revision" \
            --kconfig-file src/Kconfig \
            --kconfig-binding-file "$(linux-kconfig-binding-file v5.0)"
}

add-freetz-ng-kconfig(revision) {
    # todo: upgrade to other linux kconfig binding?
    add-linux-kconfig-binding --revision v5.0
    add-system --system freetz-ng --url https://github.com/Freetz-NG/freetz-ng
    add-kconfig-model \
        --system freetz-ng \
        --revision "$revision" \
        --kconfig-file config/Config.in \
        --kconfig-binding-file "$(linux-kconfig-binding-file v5.0)"
}

linux-tag-revisions() {
    git-tag-revisions linux | exclude-revision tree rc "v.*\..*\..*\..*"
}

# todo: other arch's
add-linux-kconfig(revision, kconfig_binding_file=) {
    add-system --system linux --url https://github.com/torvalds/linux
    local arch=x86
    if git -C "$(input-directory)/linux" ls-tree -r "$revision" --name-only | grep -q arch/i386; then
        arch=i386 # in old revisions, x86 is called i386
    fi
    add-revision --system linux --revision "$revision"
    local environment=ARCH=$arch,SRCARCH=$arch,KERNELVERSION=kcu,srctree=./,CC=cc,LD=ld,RUSTC=rustc
    if [[ -n $kconfig_binding_file ]]; then
        add-kconfig-model \
            --system linux \
            --revision "$revision" \
            --kconfig-file arch/$arch/Kconfig \
            --kconfig-binding-file "$kconfig_binding_file" \
            --environment "$environment"
    else
        add-kconfig \
            --system linux \
            --revision "$revision" \
            --kconfig-file arch/$arch/Kconfig \
            --kconfig-binding-files scripts/kconfig/*.o \
            --environment "$environment"
    fi
}

add-linux-kconfig-binding(revision) {
    add-system --system linux --url https://github.com/torvalds/linux
    add-kconfig-binding --system linux --revision "$revision" --kconfig_binding_files scripts/kconfig/*.o
}

linux-kconfig-binding-file(revision) {
    output-path "$KCONFIG_BINDINGS_OUTPUT_DIRECTORY" linux "$revision"
}

add-linux-kconfig-history(from=, to=4.18) {
    # for up to linux 2.6.9, use the kconfig parser of linux 2.6.9 for extraction, as previous versions cannot be compiled
    local first_binding_revision=v2.6.9
    add-linux-kconfig-binding --revision "$first_binding_revision"
    for revision in $(linux-tag-revisions \
        | start-at-revision "$(min-revision "$first_binding_revision" "$from")" \
        | stop-at-revision "$(min-revision "$first_binding_revision" "$to")"); do
        add-linux-kconfig \
            --revision "$revision" \
            --kconfig-binding-file "$(output-path "$KCONFIG_BINDINGS_OUTPUT_DIRECTORY" linux v2.6.9)"
    done
    # after linux 2.6.9, use the kconfig parser of the respective revision
    for revision in $(linux-tag-revisions \
        | start-at-revision "$(max-revision "$first_binding_revision" "$from")" \
        | stop-at-revision "$(max-revision "$first_binding_revision" "$to")"); do
        add-linux-kconfig --revision "$revision"
    done
}
