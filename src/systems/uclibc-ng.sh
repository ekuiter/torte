#!/bin/bash

UCLIBC_NG_URL=https://github.com/wbx-github/uclibc-ng

add-uclibc-ng-kconfig-history(from=, to=) {
    add-system --system uclibc-ng --url "$UCLIBC_NG_URL"
    add-hook-step configfix-pre-extraction-hook configfix-pre-extraction-hook-uclibc-ng
    for revision in $(git-tag-revisions uclibc-ng | start-at-revision "$from" | stop-at-revision "$to"); do
        add-revision --system uclibc-ng --revision "$revision"
        add-kconfig \
            --system uclibc-ng \
            --revision "$revision" \
            --kconfig-file extra/Configs/Config.in \
            --lkc-directory extra/config
    done
}

configfix-pre-extraction-hook-uclibc-ng(system, revision) {
    if [[ $system == uclibc-ng ]]; then
        remove-environment-variable-imports
    fi
}