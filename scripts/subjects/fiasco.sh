#!/bin/bash

add-fiasco-kconfig(revision) {
    add-linux-kconfig-binding --revision v5.0
    add-system --system fiasco --url https://github.com/kernkonzept/fiasco
    add-revision --system fiasco --revision "$revision"
    add-kconfig-model \
            --system fiasco \
            --revision "$revision" \
            --kconfig-file src/Kconfig \
            --kconfig-binding-file "$(linux-kconfig-binding-file v5.0)"
}