#!/bin/bash

# use a frozen Git copy of the original Git repository, with better availability
# UCLIBCXX_URL=git://git.busybox.net/uClibc++
UCLIBCXX_URL=https://github.com/ekuiter/torte-uclibcxx

define-system \
    --system uclibcxx \
    --kconfig-file extra/Configs/Config.in \
    --lkc-directory extra/config \
    --sample-branch master

add-uclibcxx-system() {
    add-system --system uclibcxx --url "$UCLIBCXX_URL"
}

add-uclibcxx-kconfig-tags(from=, to=) {
    add-uclibcxx-kconfig-revisions "$(git-tags uclibcxx | start-at-revision "$from" | stop-at-revision "$to")"
}
