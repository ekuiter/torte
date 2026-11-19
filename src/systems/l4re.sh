#!/bin/bash

L4RE_URL=https://github.com/kernkonzept/fiasco # fiasco is now known as the l4re microkernel

# like BusyBox, l4re generates parts of its feature model (with https://github.com/kernkonzept/fiasco/blob/master/tool/gen_kconfig)
# this is no issue as long as we don't aim to analyze every single commit that touches the feature model
# (for BusyBox, we enable this with add-busybox-kconfig-commits, and a similar approach could probably be used here)

# do not confuse src/Kconfig with build/Kconfig, only the latter is complete
define-system \
    --system l4re \
    --kconfig-file build/Kconfig \
    --lkc-directory tool/kconfig/scripts/kconfig \
    --lkc-output-directory build/scripts/kconfig \
    --sample-branch master

define-config-source --system l4re --mode generated

add-l4re-system() {
    add-hook-step read-configs-hook read-configs-hook-l4re
    add-system --system l4re --url "$L4RE_URL"
}

read-configs-hook-l4re(system, revision) {
    if [[ $system == l4re ]]; then
        prepare-l4re-generated-kconfig
    fi
}

prepare-l4re-generated-kconfig() {
    make fiasco.builddir.create >/dev/null 2>&1 || true
}
