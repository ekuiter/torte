#!/bin/bash

SOLETTA_URL=https://github.com/solettaproject/soletta
SOLETTA_BASE_OS=linux # for simplicity we assume Linux here, other options: https://github.com/solettaproject/soletta/tree/master/tools/build

define-system \
    --system soletta \
    --kconfig-file Kconfig \
    --lkc-directory tools/kconfig \
    --environment BASE_OS=$SOLETTA_BASE_OS,PREFIX=/usr,CFLAGS=-w,LDFLAGS=-L/usr/lib,BOARD_NAME=unknown \
    --sample-branch master

add-soletta-system() {
    add-hook-step configfix-pre-extraction-hook configfix-pre-extraction-hook-soletta
    add-system --system soletta --url "$SOLETTA_URL"
}

add-soletta-kconfig-tags(from=, to=) {
    add-soletta-kconfig-revisions "$(git-tags soletta | start-at-revision "$from" | stop-at-revision "$to")"
}