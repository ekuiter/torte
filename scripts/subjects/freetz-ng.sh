#!/bin/bash

add-freetz-ng-kconfig(revision) {
    add-linux-kconfig-binding --revision v5.0
    add-system --system freetz-ng --url https://github.com/Freetz-NG/freetz-ng
    add-hook-step kconfig-post-checkout-hook freetz-ng "$(to-lambda kconfig-post-checkout-hook-freetz-ng)"
    add-revision --system freetz-ng --revision "$revision"
    add-kconfig-model \
        --system freetz-ng \
        --revision "$revision" \
        --kconfig-file config/Config.in \
        --kconfig-binding-file "$(linux-kconfig-binding-file v5.0)"
}

kconfig-post-checkout-hook-freetz-ng(system, revision) {
    if [[ $system == freetz-ng ]]; then
        # ugly hack because freetz-ng is weird
        mkdir -p make/pkgs
        touch make/Config.in.generated make/external.in.generated make/pkgs/external.in.generated make/pkgs/Config.in.generated config/custom.in
    fi
}