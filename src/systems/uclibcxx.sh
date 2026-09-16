#!/bin/bash

UCLIBCXX_URL=git://git.busybox.net/uClibc++

# uClibc++ uses the C LKC frontend copied from uClibc.
# INSTALL describes the menu configuration system as Linux-like and ripped
# directly from uClibc.
#
# The language is a small, old Linux/uClibc dialect. Its lexer/parser supports
# the usual bool/tristate/int/hex/string entries plus uClibc-era aliases like
# "requires"; the model itself is tiny and has static source statements only.
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
