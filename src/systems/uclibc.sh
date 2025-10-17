#!/bin/bash

UCLIBC_URL=https://github.com/kraj/uClibc

add-uclibc-kconfig-history(from=, to=) {
    add-system --system uclibc --url "$UCLIBC_URL"
    for revision in $(git-tag-revisions uclibc | exclude-revision rc | exclude-revision svn | exclude-revision mdad | start-at-revision "$from" | stop-at-revision "$to"); do
        add-revision --system uclibc --revision "$revision"
        add-kconfig \
            --system uclibc \
            --revision "$revision" \
            --kconfig-file extra/Configs/Config.in \
            --lkc-directory extra/config
    done
}