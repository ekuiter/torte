#!/bin/bash

add-file-kconfig(file, stage=kconfig-file, kconfig_file=, lkc_binding=v6.7) {
    local url
    url=$(mktemp -d)
    kconfig_file=${kconfig_file:-$file}
    cp -R "$(input-directory)/$file" "$url"
    git -C "$url" init
    git -C "$url" add -A
    git -C "$url" commit -m .
    add-linux-lkc-binding --revision "$lkc_binding"
    add-system --system "$stage" --url "$url"
    add-revision --system "$stage" --revision HEAD
    add-kconfig-model \
        --system "$stage" \
        --revision HEAD \
        --kconfig-file "$kconfig_file" \
        --lkc-binding-file "$(linux-lkc-binding-file "$lkc_binding")"
}