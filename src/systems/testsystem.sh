#!/bin/bash

TESTSYSTEM_URL=https://github.com/rami-alfish/testsystem.git

add-testsystem-kconfig(revision) {
    #local revision="v0.0"  # oder "v0.0" wenn du getaggt hast
    add-linux-lkc-binding --revision v6.7
    add-system --system testsystem --url "$TESTSYSTEM_URL"
    add-revision --system testsystem --revision "$revision"
    add-kconfig-model \
        --system testsystem \
        --revision "$revision" \
        --kconfig-file Kconfig \
        --lkc-binding-file "$(linux-lkc-binding-file v6.7)"
}
