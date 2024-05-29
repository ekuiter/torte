#!/bin/bash

add-file-kconfig(file, stage=kconfig-file, kconfig_file=, kconfig_binding=v6.7) {
    local url
    url=$(mktemp -d)
    kconfig_file=${kconfig_file:-$file}
    cp -R "$(input-directory)/$file" "$url"
    git -C "$url" init
    git -C "$url" add -A
    git -C "$url" commit -m .
    add-linux-kconfig-binding --revision "$kconfig_binding"
    add-system --system "$stage" --url "$url"
    add-revision --system "$stage" --revision HEAD
    add-kconfig-model \
        --system "$stage" \
        --revision HEAD \
        --kconfig-file "$kconfig_file" \
        --kconfig-binding-file "$(linux-kconfig-binding-file "$kconfig_binding")"
}