#!/bin/bash

add-uclibc-ng-kconfig-history(from=, to=) {
    # environment variable ARCH, VERSION undefined
    add-system --system uclibc-ng --url https://github.com/wbx-github/uclibc-ng
    for revision in $(git-tag-revisions uclibc-ng | start-at-revision "$from" | stop-at-revision "$to"); do
        add-revision --system uclibc-ng --revision "$revision"
        add-kconfig \
            --system uclibc-ng \
            --revision "$revision" \
            --kconfig-file extra/Configs/Config.in \
            --kconfig-binding-files extra/config/zconf.tab.o
    done
}