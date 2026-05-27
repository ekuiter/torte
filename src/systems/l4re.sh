#!/bin/bash

L4RE_URL=https://github.com/kernkonzept/fiasco # fiasco is now known as the l4re microkernel

# like BusyBox, l4re generates parts of its feature model (with https://github.com/kernkonzept/fiasco/blob/master/tool/gen_kconfig)
# this is no issue as long as we don't aim to analyze every single commit that touches the feature model
# (for BusyBox, we enable this with generate-busybox-models, and a similar approach could probably be used here)

add-l4re-system() {
    add-system --system l4re --url "$L4RE_URL"
}

# do not confuse src/Kconfig with build/Kconfig, only the latter is complete
define-system \
    --system l4re \
    --kconfig-file build/Kconfig \
    --lkc-directory tool/kconfig/scripts/kconfig \
    --lkc-output-directory build/scripts/kconfig \
    --sample-branch master

add-l4re-kconfig-history(interval_name=yearly) {
    add-l4re-kconfig-sample --interval "$(interval "$interval_name")"
}
