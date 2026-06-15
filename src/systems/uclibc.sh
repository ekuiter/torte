#!/bin/bash

UCLIBC_URL=https://github.com/kraj/uClibc

define-system \
    --system uclibc \
    --kconfig-file extra/Configs/Config.in \
    --lkc-directory extra/config \
    --sample-branch master

add-uclibc-system() {
    add-hook-step configfix-pre-extraction-hook configfix-pre-extraction-hook-uclibc
    add-system --system uclibc --url "$UCLIBC_URL"
}

add-uclibc-kconfig-tags(from=, to=) {
    add-uclibc-kconfig-revisions \
        "$(git-tags uclibc | exclude-revision rc | exclude-revision svn | exclude-revision mdad | start-at-revision "$from" | stop-at-revision "$to")"
}

configfix-pre-extraction-hook-uclibc(system, revision) {
    if [[ $system == uclibc ]]; then
        remove-environment-variable-imports
    fi
}
