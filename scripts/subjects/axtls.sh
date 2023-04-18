#!/bin/bash

add-axtls-kconfig-history(from=, to=) {
    # use a frozen Git copy of the original SVN repository
    add-system --system axtls --url https://github.com/ekuiter/axTLS
    for revision in $(git-tag-revisions axtls | exclude-revision @ | start-at-revision "$from" | stop-at-revision "$to"); do
        add-kconfig \
            --system axtls \
            --revision "$revision" \
            --kconfig-file config/Config.in \
            --kconfig-binding-files config/scripts/config/*.o
    done
}