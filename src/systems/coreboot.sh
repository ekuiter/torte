#!/bin/bash

COREBOOT_URL=https://github.com/coreboot/coreboot

define-system \
    --system coreboot \
    --kconfig-file src/Kconfig \
    --lkc-directory util/kconfig \
    --lkc-output-directory build/util/kconfig \
    --environment KBUILD_KCONFIG=src/Kconfig \
    --sample-branch main

add-coreboot-system() {
    add-hook-step kconfig-post-checkout-hook kconfig-post-checkout-hook-coreboot
    add-hook-step kconfig-pre-binding-hook kconfig-pre-binding-hook-coreboot
    add-hook-step kclause-post-binding-hook kclause-post-binding-hook-coreboot
    add-system --system coreboot --url "$COREBOOT_URL"
}

add-coreboot-kconfig-tags(from=, to=) {
    add-coreboot-kconfig-revisions "$(git-tags coreboot | start-at-revision "$from" | stop-at-revision "$to")"
}

kconfig-post-checkout-hook-coreboot(system, revision) {
    if [[ $system == coreboot ]]; then
        # coreboot's .xcompile is for firmware cross tools
        # for extraction, we only need the host-built kconfig frontend
        cat > .xcompile <<'EOF'
IASL := iasl
HOSTCC ?= gcc
HOSTCXX ?= g++
CPUS ?= 1
CC := gcc
AS := as
LD := ld
NM := nm
OBJCOPY := objcopy
OBJDUMP := objdump
AR := ar
STRIP := strip
XCOMPILE_COMPLETE := 1
EOF

        # some releases declare kconfig_warnings in lkc.h but define it only in ui frontends
        # torte replaces conf.c, so provide the missing global here
        if [[ -f util/kconfig/lkc.h ]] \
            && grep -q 'extern int kconfig_warnings' util/kconfig/lkc.h \
            && ! grep -qn '^[[:space:]]*int[[:space:]]\+kconfig_warnings' util/kconfig/symbol.c; then
            printf '\n/* torte: standalone conf replacement needs the frontend warning counter */\nint kconfig_warnings = 0;\n' >> util/kconfig/symbol.c
        fi
    fi
}

kconfig-pre-binding-hook-coreboot(system, revision, lkc_directory=) {
    if [[ $system == coreboot ]]; then
        if [[ -f Makefile.inc ]]; then
            # coreboot 4.1-4.8 create a make variable named " " using "$(spc) :="
            # gnu make 4.3 rejects that before config can build, so fix it here
            perl -0pi -e '
                s/spc :=\nspc \+=\n\Q$(spc) :=\E\n\Q$(spc) +=\E/empty :=\nspc := $(empty) $(empty)/;
                s/\Q$( )\E/$(spc)/g;
            ' Makefile.inc
        fi
    fi
}

kclause-post-binding-hook-coreboot(system, revision, date_prefix=) {
    if [[ $system == coreboot ]]; then
        # board paths can contain dashes
        # kclause parses them as subtraction in generated identifiers, so replace them with underscores
        sed -i 's/-/_/g' "$(output-path "$system" "${date_prefix}$revision.kextractor")"
    fi
}
