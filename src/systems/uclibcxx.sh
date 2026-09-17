#!/bin/bash

UCLIBCXX_URL=git://git.busybox.net/uClibc++
UCLIBCXX_URL_FORK=https://github.com/ekuiter/torte-uclibcxx

define-system \
    --system uclibcxx \
    --kconfig-file extra/Configs/Config.in \
    --lkc-directory extra/config \
    --sample-branch master

add-uclibcxx-system() {
    add-system --system uclibcxx --url "$UCLIBCXX_URL" --fork-url "$UCLIBCXX_URL_FORK"
}

add-uclibcxx-kconfig-tags(from=, to=) {
    add-uclibcxx-kconfig-revisions "$(git-tags uclibcxx | start-at-revision "$from" | stop-at-revision "$to")"
}
