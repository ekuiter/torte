#!/bin/bash

add-busybox-kconfig-history(from=, to=) {
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