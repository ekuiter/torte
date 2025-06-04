#!/bin/bash

add-testsystem-kconfig(revision) {
    #local revision="v0.0"  # oder "v0.0" wenn du getaggt hast
    add-linux-kconfig-binding --revision v6.7
    add-system --system testsystem --url https://github.com/rami-alfish/testsystem.git
    add-revision --system testsystem --revision "$revision"
    add-kconfig-model \
        --system testsystem \
        --revision "$revision" \
        --kconfig-file Kconfig \
        --kconfig-binding-file "$(linux-kconfig-binding-file v6.7)"
}
