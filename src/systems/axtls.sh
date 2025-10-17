#!/bin/bash

AXTLS_URL=https://github.com/ekuiter/axTLS

add-axtls-kconfig-history(from=, to=) {
    add-system --system axtls --url "$AXTLS_URL"
    for revision in $(git-tag-revisions axtls | exclude-revision @ | start-at-revision "$from" | stop-at-revision "$to"); do
        add-revision --system axtls --revision "$revision"
        add-kconfig \
            --system axtls \
            --revision "$revision" \
            --kconfig-file config/Config.in \
            --lkc-directory config/scripts/config
    done
}