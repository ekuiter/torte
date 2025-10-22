#!/bin/bash

# use a frozen Git copy of the original SVN repository, including newer versions up to 2.1.5
AXTLS_URL=https://github.com/ekuiter/torte-axTLS

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