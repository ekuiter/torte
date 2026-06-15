#!/bin/bash

UCLIBC_NG_URL=https://github.com/wbx-github/uclibc-ng

define-system \
    --system uclibc-ng \
    --kconfig-file extra/Configs/Config.in \
    --lkc-directory extra/config \
    --sample-branch master

add-uclibc-ng-system() {
    add-hook-step configfix-pre-extraction-hook configfix-pre-extraction-hook-uclibc-ng
    add-system --system uclibc-ng --url "$UCLIBC_NG_URL"
}

add-uclibc-ng-kconfig-tags(from=, to=) {
    add-uclibc-ng-kconfig-revisions \
        "$(git-tags uclibc-ng | start-at-revision "$from" | stop-at-revision "$to")"
}

configfix-pre-extraction-hook-uclibc-ng(system, revision) {
    if [[ $system == uclibc-ng ]]; then
        remove-environment-variable-imports
    fi
}
