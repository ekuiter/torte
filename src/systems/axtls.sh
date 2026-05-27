#!/bin/bash

# use a frozen Git copy of the original SVN repository, including newer versions up to 2.1.5
AXTLS_URL=https://github.com/ekuiter/torte-axTLS

add-axtls-system() {
    add-system --system axtls --url "$AXTLS_URL"
    add-hook-step configfix-pre-extraction-hook configfix-pre-extraction-hook-axtls
}

define-system \
    --system axtls \
    --kconfig-file config/Config.in \
    --lkc-directory config/scripts/config \
    --sample-branch main

add-axtls-kconfig-history(from=, to=) {
    add-axtls-kconfig-revisions \
        "$(git-tag-revisions axtls | exclude-revision @ | start-at-revision "$from" | stop-at-revision "$to")"
}

configfix-pre-extraction-hook-axtls(system, revision) {
    if [[ $system == axtls ]]; then
        wrap-source-statements-in-double-quotes
    fi
}
