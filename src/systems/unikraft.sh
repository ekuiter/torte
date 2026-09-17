#!/bin/bash

UNIKRAFT_URL=https://github.com/unikraft/unikraft

define-system \
    --system unikraft \
    --kconfig-file Config.uk \
    --lkc-directory support/kconfig \
    --lkc-target torte-conf \
    --lkc-output-directory build/kconfig \
    --environment CONFIG_=CONFIG_,KCONFIG_CONFIG=.config,KCONFIG_AUTOCONFIG=build/kconfig/auto.conf,KCONFIG_AUTOHEADER=build/include/uk/bits/config.h,KCONFIG_TRISTATE=build/kconfig/tristate.config,HOST_ARCH=x86_64,BUILD_DIR=build,UK_BASE=.,UK_APP=.,UK_CONFIG=.config,UK_FULLVERSION=0,UK_CODENAME=,UK_ARCH=x86_64,KCONFIG_DIR=build/kconfig,KCONFIG_LIB_BASE=lib,KCONFIG_ELIB_DIRS=,KCONFIG_PLAT_BASE=plat,KCONFIG_EPLAT_DIRS=,KCONFIG_DRIV_BASE=drivers,KCONFIG_EAPP_DIR=,KCONFIG_EXCLUDEDIRS=,UK_NAME=unikraft,HOSTCC=gcc,HOSTCXX=g++,CC=gcc \
    --sample-branch staging

add-unikraft-system() {
    add-hook-step kconfig-pre-binding-hook kconfig-pre-binding-hook-unikraft
    add-system --system unikraft --url "$UNIKRAFT_URL"
}

add-unikraft-kconfig-tags(from=, to=) {
    add-unikraft-kconfig-revisions "$(git-tags unikraft | start-at-revision "$from" | stop-at-revision "$to")"
}

kconfig-pre-binding-hook-unikraft(system, revision, lkc_directory=) {
    if [[ $system == unikraft ]]; then
        # an empty .config makes config targets depend on the lkc binary
        touch .config
        write-unikraft-minimal-lkc-target

        # Config.uk shell sources write submenu files below KCONFIG_DIR
        mkdir -p build/kconfig build/include/uk/bits
    fi
}

write-unikraft-minimal-lkc-target() {
    if [[ -f Makefile ]]; then
        cat > Makefile <<'EOF'
.PHONY: torte-conf

# torte: build only the replacement conf frontend
torte-conf:
	$(MAKE) --no-print-directory CC="$(HOSTCC)" HOSTCC="$(HOSTCC)" obj=$(CURDIR)/build/kconfig -C support/kconfig -f Makefile.br $(CURDIR)/build/kconfig/conf
EOF
    fi
}
